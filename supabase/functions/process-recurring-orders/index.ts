import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Process all due recurring orders
export default {
  fetch: async (req: Request) => {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const todayUtc = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"

    const { error: reminderError } = await supabase.rpc(
      "notify_upcoming_recurring_low_balance",
    );
    if (reminderError) {
      console.error("Error sending recurring balance reminders:", reminderError);
      return new Response(
        JSON.stringify({ error: reminderError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // Fetch all recurring orders that are:
    //  (a) active
    //  (b) due now (next_run_at <= now)
    //  (c) NOT already processed today (duplicate guard layer 1)
    //
    // The RPC itself also checks last_processed_date inside a FOR UPDATE
    // lock — that is duplicate guard layer 2.
    const { data: dueOrders, error: fetchError } = await supabase
      .from("recurring_order")
      .select("id")
      .eq("status", "active")
      .lte("next_run_at", new Date().toISOString())
      .or(`last_processed_date.is.null,last_processed_date.lt.${todayUtc}`);

    if (fetchError) {
      console.error("Error fetching due orders:", fetchError);
      return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
    }

    if (!dueOrders || dueOrders.length === 0) {
      return new Response(JSON.stringify({ message: "No due orders found" }), { status: 200 });
    }

    const results = [];

    for (const order of dueOrders) {
      const { data: rpcResult, error: rpcError } = await supabase
        .rpc("fulfill_recurring_order", { p_recurring_order_id: order.id });

      if (rpcError) {
        console.error(`Error fulfilling order ${order.id}:`, rpcError);
        results.push({ id: order.id, status: "error", error: rpcError.message });
      } else {
        console.log(`Fulfilled order ${order.id}:`, rpcResult);
        results.push({ id: order.id, status: "success", result: rpcResult });
      }
    }

    return new Response(JSON.stringify({ processed: results.length, results }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};

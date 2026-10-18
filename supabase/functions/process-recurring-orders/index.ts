import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Manual / external trigger for recurring-order processing.
//
// The real schedule is pg_cron (migration
// 20261018110000_recurring_orders_server_authoritative.sql): 00:00
// Asia/Colombo places today's + tomorrow's occurrences, and an hourly job
// retries ones waiting for funds/stock. This function just runs the same
// SQL — process_due_recurring_orders() — so both paths behave identically
// (and fulfillment is idempotent, so running both is harmless).
//
// Body (optional): { "retry_only": true }
// Requires the service-role key as the bearer token: verify_jwt is off for
// this function, so without this check anyone could trigger a run.
export default {
  fetch: async (req: Request) => {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const auth = req.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${supabaseServiceKey}`) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    let retryOnly = false;
    try {
      const body = await req.json();
      retryOnly = body?.retry_only === true;
    } catch {
      // No/invalid body: full run.
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const { data, error } = await supabase.rpc("process_due_recurring_orders", {
      p_retry_only: retryOnly,
    });

    if (error) {
      console.error("process_due_recurring_orders failed:", error.message);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log("Recurring orders processed:", JSON.stringify(data));
    return new Response(JSON.stringify(data), {
      headers: { "Content-Type": "application/json" },
    });
  },
};

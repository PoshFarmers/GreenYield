// =============================================================================
// suggest-listing — Snap-to-List AI assistant.
//
// Input  (POST, JSON, caller's JWT in Authorization):
//   { image_base64: string, mime_type?: string, language?: "en"|"si"|"ta" }
// Output (200):
//   { crop_id: string|null, confidence: number(0-1), description: string,
//     model: string }
// Errors (non-200): { error: <code> } where code is one of
//   unauthorized | bad_request | image_too_large | no_crops | cooldown |
//   daily_cap | not_configured | rate_limited | timeout | invalid_output |
//   upstream_error
//
// The app treats every error as "fall back to the sample suggestion", so
// nothing here has to be perfect — but it must never return a crop the
// farmer doesn't grow, and never leak the API key or the image.
//
// Secrets (supabase secrets set ...):
//   GEMINI_API_KEY   required
//   GEMINI_MODEL     optional, default "gemini-2.5-flash" (any free-tier
//                    Flash / Flash-Lite model that accepts images)
// =============================================================================
import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const COOLDOWN_SECONDS = 10;
const DAILY_CAP = 25;
// ~1.5 MB of JPEG once decoded; the app sends ≤1600px images.
const MAX_BASE64_CHARS = 2_000_000;
const GEMINI_TIMEOUT_MS = 15_000;
const MAX_DESCRIPTION_CHARS = 280;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const LANGUAGE_NAMES: Record<string, string> = {
  en: "English",
  si: "Sinhala",
  ta: "Tamil",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const fail = (code: string, status: number) => json({ error: code }, status);

type Crop = { id: string; name: string };

export default {
  fetch: async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return fail("bad_request", 405);

    // --- Auth: who is asking? ------------------------------------------------
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return fail("unauthorized", 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (userError || !user) return fail("unauthorized", 401);

    // --- Input -----------------------------------------------------------------
    let body: { image_base64?: string; mime_type?: string; language?: string };
    try {
      body = await req.json();
    } catch {
      return fail("bad_request", 400);
    }
    const image = body.image_base64;
    if (!image || typeof image !== "string") return fail("bad_request", 400);
    if (image.length > MAX_BASE64_CHARS) return fail("image_too_large", 413);
    const mimeType = ["image/jpeg", "image/png", "image/webp", "image/heic"].includes(
        body.mime_type ?? "",
      )
      ? body.mime_type!
      : "image/jpeg";
    const language = LANGUAGE_NAMES[body.language ?? ""] ? body.language! : "en";

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) return fail("not_configured", 503);

    // --- The farmer's own crops (RLS: own rows only) ---------------------------
    // A listing can only be for a crop on the farmer's menu, so that's the
    // only list the model may choose from.
    const { data: cropRows, error: cropError } = await userClient
      .from("farmer_crop")
      .select("crop_id, crop(name)")
      .eq("farmer_profile_id", user.id);
    if (cropError) return fail("upstream_error", 502);
    const crops: Crop[] = (cropRows ?? [])
      .map((r: { crop_id: string; crop: { name: string } | null }) => ({
        id: r.crop_id,
        name: r.crop?.name ?? "",
      }))
      .filter((c) => c.name);
    if (crops.length === 0) return fail("no_crops", 422);

    // --- Quota (cooldown + daily cap), claimed atomically ----------------------
    const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: claim, error: claimError } = await admin.rpc("claim_ai_request", {
      p_user_id: user.id,
      p_feature: "suggest_listing",
      p_cooldown_seconds: COOLDOWN_SECONDS,
      p_daily_cap: DAILY_CAP,
    });
    if (claimError) return fail("upstream_error", 502);
    if (claim === "cooldown") return fail("cooldown", 429);
    if (claim === "daily_cap") return fail("daily_cap", 429);

    // --- Ask Gemini ------------------------------------------------------------
    const model = Deno.env.get("GEMINI_MODEL") || "gemini-2.5-flash";
    const result = await askGemini({ apiKey, model, image, mimeType, language, crops });
    if ("error" in result) {
      const status = result.error === "rate_limited" ? 429
        : result.error === "timeout" ? 504
        : 502;
      return fail(result.error, status);
    }

    // --- Validate ----------------------------------------------------------------
    const known = new Set(crops.map((c) => c.id));
    const cropId = typeof result.crop_id === "string" && known.has(result.crop_id)
      ? result.crop_id
      : null;
    const confidence = cropId === null
      ? 0
      : Math.min(1, Math.max(0, Number(result.confidence) || 0));

    return json({
      crop_id: cropId,
      confidence,
      description: sanitize(result.description),
      model,
    });
  },
};

/** Plain text only, one or two short sentences, bounded length. */
function sanitize(value: unknown): string {
  if (typeof value !== "string") return "";
  const text = value
    .replace(/[*_#`>|]/g, "") // markdown remnants
    .replace(/\s+/g, " ")
    .trim();
  return text.length > MAX_DESCRIPTION_CHARS
    ? text.slice(0, MAX_DESCRIPTION_CHARS - 1).trimEnd() + "…"
    : text;
}

type GeminiAnswer = { crop_id?: unknown; confidence?: unknown; description?: unknown };

async function askGemini(args: {
  apiKey: string;
  model: string;
  image: string;
  mimeType: string;
  language: string;
  crops: Crop[];
}): Promise<GeminiAnswer | { error: string }> {
  const { apiKey, model, image, mimeType, language, crops } = args;

  const cropList = crops.map((c) => `- ${c.id}: ${c.name}`).join("\n");
  const instruction = [
    "You help a Sri Lankan farmer list fresh produce for sale.",
    "Look at the photo and decide which ONE crop from this list it shows:",
    cropList,
    "",
    'Reply with JSON: {"crop_id": <an id from the list, or "unknown">,',
    '"confidence": <0 to 1>, "description": <text>}.',
    'Use "unknown" if the photo is not produce or matches none of the listed crops.',
    `"description": 1-2 short, factual sentences for buyers about how the produce`,
    "looks (colour, size, freshness, condition). No prices, no health or",
    "medical claims, no invented facts about where or how it was grown.",
    `Write the description in ${LANGUAGE_NAMES[language]}.`,
  ].join("\n");

  const schema = {
    type: "object",
    properties: {
      crop_id: { type: "string" },
      confidence: { type: "number" },
      description: { type: "string" },
    },
    required: ["crop_id", "confidence", "description"],
  };

  const contents = [{
    role: "user",
    parts: [
      { text: instruction },
      { inlineData: { mimeType, data: image } },
    ],
  }];

  // The structured-output request format has changed across API versions.
  // Try the current form first, then the older ones, then plain prompting —
  // the instruction above asks for JSON either way.
  const generationConfigs: Record<string, unknown>[] = [
    { responseFormat: { text: { mimeType: "application/json", schema } }, temperature: 0.2 },
    { responseMimeType: "application/json", responseJsonSchema: schema, temperature: 0.2 },
    { responseMimeType: "application/json", temperature: 0.2 },
    { temperature: 0.2 },
  ];

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

  for (const generationConfig of generationConfigs) {
    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({ contents, generationConfig }),
        signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      });
    } catch (e) {
      const name = (e as Error)?.name;
      return { error: name === "TimeoutError" || name === "AbortError" ? "timeout" : "upstream_error" };
    }

    if (res.status === 429) return { error: "rate_limited" };
    // 400 = this request shape isn't accepted by this model/API version;
    // try the next one. Anything else non-OK is a real upstream problem.
    if (res.status === 400) continue;
    if (!res.ok) {
      console.error("gemini error", res.status); // never log the body/image
      return { error: "upstream_error" };
    }

    const data = await res.json().catch(() => null);
    const text: string = (data?.candidates?.[0]?.content?.parts ?? [])
      .filter((p: { text?: string; thought?: boolean }) => p.text && !p.thought)
      .map((p: { text: string }) => p.text)
      .join("");
    const parsed = parseJsonObject(text);
    return parsed ?? { error: "invalid_output" };
  }

  console.error("gemini: no accepted request format for model", model);
  return { error: "upstream_error" };
}

/** First {...} block in the text, parsed; tolerates code fences / prose. */
function parseJsonObject(text: string): GeminiAnswer | null {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end <= start) return null;
  try {
    const value = JSON.parse(text.slice(start, end + 1));
    return value && typeof value === "object" ? value as GeminiAnswer : null;
  } catch {
    return null;
  }
}

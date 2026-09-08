// Shared CORS + response helpers for Orchestrio Edge Functions.
export const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_URL") ?? "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-request-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200, requestId?: string): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...(requestId ? { "x-request-id": requestId } : {}),
    },
  });
}

export function ok(data: unknown, requestId?: string) {
  return json({ ok: true, data }, 200, requestId);
}

export function fail(code: string, message: string, status = 400, requestId?: string) {
  return json({ ok: false, error: { code, message } }, status, requestId);
}

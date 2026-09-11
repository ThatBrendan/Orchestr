// Explicit browser origins; APP_URL supplies the production origin.
export function corsHeaders(req: Request): Record<string, string> {
  const allowed = new Set(["http://localhost:5173", "http://127.0.0.1:5173"]);
  for (const value of [Deno.env.get("APP_URL"), ...(Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",")]) {
    if (!value?.trim()) continue;
    try { allowed.add(new URL(value.trim()).origin); } catch { /* Ignore invalid configuration. */ }
  }
  const origin = req.headers.get("origin") ?? "";
  return {
    ...(allowed.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-request-id",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "600",
  };
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

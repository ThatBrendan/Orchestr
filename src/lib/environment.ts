import * as v from "valibot";

const Schema = v.object({
  VITE_SUPABASE_URL: v.pipe(v.string(), v.url()),
  VITE_SUPABASE_PUBLISHABLE_KEY: v.pipe(v.string(), v.minLength(20)),
  VITE_APP_ENV: v.picklist(["development", "staging", "production"]),
  VITE_APP_URL: v.pipe(v.string(), v.url()),
  VITE_SENTRY_DSN: v.optional(v.string()),
});

export function parsePublicEnvironment(env: Record<string, unknown>) {
  for (const [name, value] of Object.entries(env)) {
    if (!name.startsWith("VITE_")) continue;
    let privilegedJwt = false;
    if (typeof value === "string" && value.split(".").length === 3) {
      try {
        const payload = JSON.parse(atob(value.split(".")[1]!.replace(/-/g, "+").replace(/_/g, "/"))) as { role?: string };
        privilegedJwt = payload.role === "service_role";
      } catch { /* Non-JWT public values are validated below. */ }
    }
    if (privilegedJwt || /SERVICE_ROLE|SECRET|PRIVATE_KEY|PASSWORD|ACCESS_TOKEN|DATABASE_URL/i.test(name)
      || (typeof value === "string" && (/^sb_secret_/.test(value) || value.includes("-----BEGIN")))) {
      throw new Error(`Privileged browser configuration rejected: ${name}.`);
    }
  }
  const result = v.safeParse(Schema, env);
  // Never print validation inputs: a misnamed key could contain privileged material.
  if (!result.success) throw new Error("Invalid public environment configuration. Check .env.example and ENVIRONMENTS.md.");
  const output = result.output;
  const key = output.VITE_SUPABASE_PUBLISHABLE_KEY;
  if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) {
    try {
      const payload = JSON.parse(atob(key.split(".")[1]!.replace(/-/g, "+").replace(/_/g, "/"))) as { role?: string; ref?: string };
      if (key.split(".").length !== 3 || payload.role !== "anon") throw new Error();
      if (payload.ref && new URL(output.VITE_SUPABASE_URL).hostname !== `${payload.ref}.supabase.co`) throw new Error();
    } catch { throw new Error("Use a publishable key or legacy anon key, never a privileged key."); }
  }
  for (const value of [output.VITE_SUPABASE_URL, output.VITE_APP_URL]) {
    const url = new URL(value);
    const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (url.username || url.password || url.search || url.hash || url.pathname !== "/"
      || (url.protocol !== "https:" && !(local && url.protocol === "http:"))) {
      throw new Error("App and Supabase URLs must be HTTPS origins (HTTP allowed only on loopback).");
    }
  }
  return output;
}

import * as v from "valibot";

/**
 * Build-time public configuration (docs/TECHNICAL_ARCHITECTURE.md §21).
 * Validated at module load — fails fast if a required var is missing/malformed.
 * Only PUBLIC values. A build must never contain a service-role key.
 */
const Schema = v.object({
  VITE_SUPABASE_URL: v.pipe(v.string(), v.url()),
  VITE_SUPABASE_ANON_KEY: v.pipe(v.string(), v.minLength(20)),
  VITE_APP_ENV: v.picklist(["development", "staging", "production"]),
  VITE_APP_URL: v.pipe(v.string(), v.url()),
  VITE_SENTRY_DSN: v.optional(v.string()),
});

const parsed = v.safeParse(Schema, import.meta.env);
if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error("Invalid environment configuration:", v.flatten(parsed.issues));
  throw new Error("Invalid environment configuration — see console.");
}

// Guard: refuse to build with a leaked privileged key in client env.
for (const key of Object.keys(import.meta.env)) {
  if (/SERVICE_ROLE|SECRET|PRIVATE_KEY/i.test(key)) {
    throw new Error(`Refusing to run: privileged env var "${key}" must not be in the client bundle.`);
  }
}

export const config = Object.freeze({
  supabaseUrl: parsed.output.VITE_SUPABASE_URL,
  supabaseAnonKey: parsed.output.VITE_SUPABASE_ANON_KEY,
  env: parsed.output.VITE_APP_ENV,
  appUrl: parsed.output.VITE_APP_URL,
  sentryDsn: parsed.output.VITE_SENTRY_DSN,
  isDev: parsed.output.VITE_APP_ENV === "development",
});

/** Product name — resolved: "Orchestr". Lives in one place. */
export const APP_NAME = "Orchestr";

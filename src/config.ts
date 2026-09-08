import * as v from "valibot";

/**
 * Build-time public configuration.
 * Only public browser-safe values belong here.
 */
const Schema = v.object({
  VITE_SUPABASE_URL: v.pipe(v.string(), v.url()),
  VITE_SUPABASE_PUBLISHABLE_KEY: v.pipe(v.string(), v.minLength(20)),
  VITE_APP_ENV: v.picklist(["development", "staging", "production"]),
  VITE_APP_URL: v.pipe(v.string(), v.url()),
  VITE_SENTRY_DSN: v.optional(v.string()),
});

const parsed = v.safeParse(Schema, import.meta.env);

if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error(
    "Invalid environment configuration:",
    v.flatten(parsed.issues),
  );

  throw new Error(
    "Invalid environment configuration — see console.",
  );
}

/**
 * Guard against accidentally shipping privileged credentials.
 */
for (const key of Object.keys(import.meta.env)) {
  if (/SERVICE_ROLE|SECRET|PRIVATE_KEY/i.test(key)) {
    throw new Error(
      `Refusing to run: privileged env var "${key}" must not be in the client bundle.`,
    );
  }
}

export const config = Object.freeze({
  supabaseUrl: parsed.output.VITE_SUPABASE_URL,
  supabasePublishableKey:
    parsed.output.VITE_SUPABASE_PUBLISHABLE_KEY,
  env: parsed.output.VITE_APP_ENV,
  appUrl: parsed.output.VITE_APP_URL,
  sentryDsn: parsed.output.VITE_SENTRY_DSN,
  isDev:
    parsed.output.VITE_APP_ENV === "development",
});

/** Product name — resolved: Orchestrio. */
export const APP_NAME = "Orchestrio";

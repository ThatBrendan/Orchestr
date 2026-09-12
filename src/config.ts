import { parsePublicEnvironment } from "./lib/environment";

const output = parsePublicEnvironment(import.meta.env);

export const config = Object.freeze({
  supabaseUrl: output.VITE_SUPABASE_URL,
  supabasePublishableKey:
    output.VITE_SUPABASE_PUBLISHABLE_KEY,
  env: output.VITE_APP_ENV,
  appUrl: output.VITE_APP_URL,
  sentryDsn: output.VITE_SENTRY_DSN,
  isDev:
    output.VITE_APP_ENV === "development",
});

export { APP_NAME, PUBLIC_CONTACT_EMAIL, PUBLIC_ORIGIN } from "./publicSite";

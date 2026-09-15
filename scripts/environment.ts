import { createHash } from "node:crypto";
import { parsePublicEnvironment } from "../src/lib/environment";
import production from "./production-project.json";

/** Fingerprint is a fail-closed guard, not a connection target or credential. */
export function isKnownProduction(ref: string) {
  return createHash("sha256").update(ref).digest("hex") === production.sha256;
}

export function prepareEnvironment(input: Record<string, string | undefined>, command: "build" | "serve") {
  const env = { ...input };
  const vercel = env.VERCEL === "1";
  if (vercel) {
    if (!["production", "preview", "development"].includes(env.VERCEL_ENV ?? "")) throw new Error("Missing or unsupported VERCEL_ENV.");
    if (env.VERCEL_ENV === "production") {
      if (env.VITE_APP_ENV !== "production" || env.VERCEL_GIT_COMMIT_REF !== "main") throw new Error("Production requires main and VITE_APP_ENV=production.");
    } else if (env.VERCEL_ENV === "preview") {
      if (env.VITE_APP_ENV !== "staging") throw new Error("Preview requires VITE_APP_ENV=staging.");
      // Email links must return to the branch origin where the PKCE flow began,
      // not the different immutable deployment hostname supplied by VERCEL_URL.
      const previewHost = env.VERCEL_BRANCH_URL || env.VERCEL_URL;
      if (!previewHost || !/^[a-z0-9.-]+$/i.test(previewHost)) throw new Error("Missing valid Vercel preview hostname.");
      env.VITE_APP_URL = `https://${previewHost}`;
    } else if (env.VITE_APP_ENV === "production") throw new Error("Vercel Development cannot target production.");
  }
  const publicConfig = parsePublicEnvironment(env);
  const url = new URL(publicConfig.VITE_SUPABASE_URL);
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  const ref = url.hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)?.[1];
  if (!local && !ref) throw new Error("Use the canonical Supabase project URL for target verification.");
  if (command === "serve" && publicConfig.VITE_APP_ENV === "production") throw new Error("Development server cannot run with production configuration.");
  if (publicConfig.VITE_APP_ENV === "production") {
    if (!ref || !isKnownProduction(ref)) throw new Error("Production backend does not match the approved project.");
    if (["localhost", "127.0.0.1", "[::1]"].includes(new URL(publicConfig.VITE_APP_URL).hostname)) throw new Error("Production app URL cannot be local.");
  } else {
    if (createHash("sha256").update(publicConfig.VITE_SUPABASE_PUBLISHABLE_KEY).digest("hex") === production.publishableKeySha256) {
      throw new Error("Known production publishable key blocked in development/staging.");
    }
    if (ref && isKnownProduction(ref)) throw new Error("Production backend blocked in development/staging. Configure an isolated backend in .env.local or Vercel.");
    if (ref && ref !== env.ORCHESTR_STAGING_PROJECT_REF) throw new Error("Backend must match explicitly configured ORCHESTR_STAGING_PROJECT_REF.");
    if ((vercel && env.VERCEL_ENV === "preview") || publicConfig.VITE_APP_ENV === "staging") {
      if (local) throw new Error("Staging/Preview requires an isolated hosted backend.");
    }
  }
  return publicConfig;
}

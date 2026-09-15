import { readAuthLink } from "./authPolicy";
import { createClient } from "@supabase/supabase-js";
import { config } from "@/config";
import type { Database } from "@/types/database";

/**
 * Single typed browser client.
 * The publishable key is safe for browser use.
 * Supabase RLS remains the authorization boundary.
 */
export const initialAuthLink = readAuthLink(typeof window === "undefined" ? config.appUrl : window.location.href);

export const supabase = createClient<Database>(
  config.supabaseUrl,
  config.supabasePublishableKey,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: "pkce",
    },
  },
);
import { createClient } from "@supabase/supabase-js";
import { config } from "@/config";
import type { Database } from "@/types/database";

/**
 * Single typed browser client (docs/TECHNICAL_ARCHITECTURE.md §8.1).
 * The anon key is public by design; RLS protects data.
 */
export const supabase = createClient<Database>(config.supabaseUrl, config.supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: "pkce",
  },
});

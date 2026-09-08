import { storeToRefs } from "pinia";
import { useAuthStore } from "@/stores/auth";
import { supabase } from "@/lib/supabase";
import { queryClient } from "@/lib/query-client";
import { toAppError } from "@/lib/errors";
import { config } from "@/config";
import { logger } from "@/lib/logger";

let wired = false;

/**
 * Auth composable (docs/TECHNICAL_ARCHITECTURE.md §5, §10).
 * `initAuth()` wires the session listener ONCE at app root.
 */
export function initAuth() {
  if (wired) return;
  wired = true;
  const store = useAuthStore();

  void supabase.auth.getSession().then(({ data }) => {
    store.setSession(data.session);
    store.markReady();
  });

  supabase.auth.onAuthStateChange((event, session) => {
    store.setSession(session);
    if (!store.ready) store.markReady();
    if (event === "SIGNED_OUT") {
      queryClient.clear();
    }
    logger.debug("auth state", { event });
  });
}

export function useAuth() {
  const store = useAuthStore();
  const { user, session, ready, isAuthenticated, userId, email } = storeToRefs(store);

  function callbackUrl(redirectPath?: string | null) {
    const base = `${config.appUrl}/auth/callback`;
    return redirectPath && redirectPath.startsWith("/")
      ? `${base}?redirect=${encodeURIComponent(redirectPath)}`
      : base;
  }

  async function signInWithPassword(emailAddr: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email: emailAddr, password });
    if (error) throw toAppError(error);
  }

  /**
   * Sign up with email + password.
   * Returns `needsConfirmation` = true when Supabase is configured to require
   * email confirmation (no session yet). The caller must NOT treat the user as
   * signed in in that case (spec §15).
   */
  async function signUpWithPassword(
    emailAddr: string,
    password: string,
    redirectPath?: string | null,
  ): Promise<{ needsConfirmation: boolean }> {
    const { data, error } = await supabase.auth.signUp({
      email: emailAddr,
      password,
      options: { emailRedirectTo: callbackUrl(redirectPath) },
    });
    if (error) throw toAppError(error);
    return { needsConfirmation: !data.session };
  }

  async function signOut() {
    await supabase.auth.signOut();
    queryClient.clear();
    store.reset();
  }

  return {
    user,
    session,
    ready,
    isAuthenticated,
    userId,
    email,
    signInWithPassword,
    signUpWithPassword,
    signOut,
  };
}

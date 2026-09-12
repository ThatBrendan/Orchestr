import { trackProductEvent } from "@/lib/analytics";
import { storeToRefs } from "pinia";
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { useProjectContextStore } from "@/stores/project-context";
import { supabase } from "@/lib/supabase";
import { queryClient } from "@/lib/query-client";
import { AppError, toAuthAppError } from "@/lib/errors";
import { config } from "@/config";
import { logger } from "@/lib/logger";

let wired = false;
const signingOut = ref(false);

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
      useProjectContextStore().clear();
    }
    logger.debug("auth state", { event });
  });
}

export function useAuth() {
  const router = useRouter();
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
    if (error) throw toAuthAppError(error);
    trackProductEvent("login_completed");
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
    if (error) throw toAuthAppError(error);
    if (data.session) trackProductEvent("signup_completed");
    else trackProductEvent("signup_confirmation_requested");
    return { needsConfirmation: !data.session };
  }

  async function signOut() {
    if (signingOut.value) return;
    signingOut.value = true;
    try {
      let remoteSignOutFailed = false;
      try {
        const { error } = await supabase.auth.signOut();
        if (error) throw error;
      } catch {
        // The installed SDK can emit SIGNED_OUT even when remote revocation
        // fails. Respect that local logout; never leave a stale protected page.
        if (store.isAuthenticated) {
          throw new AppError("auth", "Couldn't sign out. Check your connection and try again.");
        }
        remoteSignOutFailed = true;
      }
      store.reset();
      useProjectContextStore().clear();
      // Preserve the existing full cache reset, including protected mutations.
      queryClient.clear();
      await router.replace("/");
      if (remoteSignOutFailed) {
        throw new AppError("auth", "Signed out on this device, but couldn't confirm sign-out on other devices. Sign in and try again to retry.");
      }
    } finally {
      signingOut.value = false;
    }
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
    signingOut,
  };
}

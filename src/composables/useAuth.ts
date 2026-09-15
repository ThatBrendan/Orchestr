import type { Session } from "@supabase/supabase-js";
import { trackProductEvent } from "@/lib/analytics";
import { storeToRefs } from "pinia";
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { useProjectContextStore } from "@/stores/project-context";
import { supabase, initialAuthLink } from "@/lib/supabase";
import { queryClient } from "@/lib/query-client";
import { AppError, toAuthAppError } from "@/lib/errors";
import { authCallbackUrl, passwordError } from "@/lib/authPolicy";
import { config } from "@/config";
import { logger } from "@/lib/logger";

let wired = false;
const signingOut = ref(false);

/**
 * Auth composable (docs/TECHNICAL_ARCHITECTURE.md §5, §10).
 * `initAuth()` wires the session listener ONCE at app root.
 */
export function initAuth(onRecovery: () => void = () => {}) {
  if (wired) return;
  wired = true;
  const store = useAuthStore();

  function applySession(session: Session | null) {
    if (store.userId !== (session?.user.id ?? null)) {
      queryClient.clear();
      useProjectContextStore().clear();
      if (store.userId) store.setRecovery(false);
    }
    store.setSession(session);
    store.restoreRecovery();
  }

  supabase.auth.onAuthStateChange((event, session) => {
    applySession(session);
    if (event === "PASSWORD_RECOVERY" && session) {
      store.setRecovery(true);
      // Do not await other auth operations while the SDK holds its session lock.
      setTimeout(onRecovery, 0);
    }
    if (event === "SIGNED_OUT") {
      store.setRecovery(false);
      queryClient.clear();
      useProjectContextStore().clear();
    }
    logger.debug("auth state", { event });
  });

  void (async () => {
    try {
      // The SDK owns PKCE exchange. Waiting for initialize also exposes invalid-link errors.
      const initialized = await supabase.auth.initialize();
      const { data, error } = await supabase.auth.getSession();
      // A PKCE code left in the URL was not exchanged (e.g. another browser
      // has no verifier). An unrelated existing session must not validate that link.
      const unconsumedCode = new URL(window.location.href).searchParams.has("code");
      store.linkError = initialAuthLink.hasError || !!initialized.error || !!error || unconsumedCode;
      applySession(data.session);
      if (initialAuthLink.isLink && initialAuthLink.recovery && !store.linkError && data.session) {
        store.setRecovery(true);
      }
    } catch {
      store.linkError = true;
      applySession(null);
    } finally {
      store.markReady();
    }
  })();
}

export function useAuth() {
  const router = useRouter();
  const store = useAuthStore();
  const { user, session, ready, isAuthenticated, userId, email } = storeToRefs(store);

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
    const validation = passwordError(password);
    if (validation) throw new AppError("validation", validation);
    const { data, error } = await supabase.auth.signUp({
      email: emailAddr,
      password,
      options: { emailRedirectTo: authCallbackUrl(config.appUrl, redirectPath, "signup") },
    });
    if (error) throw toAuthAppError(error);
    if (data.session) trackProductEvent("signup_completed");
    else trackProductEvent("signup_confirmation_requested");
    return { needsConfirmation: !data.session };
  }

  async function resendConfirmation(emailAddr: string, redirectPath?: string | null) {
    const { error } = await supabase.auth.resend({
      type: "signup", email: emailAddr,
      options: { emailRedirectTo: authCallbackUrl(config.appUrl, redirectPath, "signup") },
    });
    if (error) throw toAuthAppError(error, "email");
  }

  async function requestPasswordReset(emailAddr: string) {
    const { error } = await supabase.auth.resetPasswordForEmail(emailAddr, {
      redirectTo: authCallbackUrl(config.appUrl, null, "recovery"),
    });
    // Account-dependent failures get the same response as an accepted request.
    if (error && !["user_not_found", "email_not_confirmed", "user_banned"].includes(error.code ?? "")) {
      throw toAuthAppError(error, "email");
    }
  }

  async function updatePassword(password: string, confirmation: string, nonce?: string) {
    const validation = passwordError(password, confirmation);
    if (validation) throw new AppError("validation", validation);
    const { data, error: sessionError } = await supabase.auth.getUser();
    if (sessionError || !data.user || data.user.id !== store.userId) {
      throw new AppError("auth", "Your session has expired. Log in or request a new password reset link.");
    }
    const { error } = await supabase.auth.updateUser({ password, ...(nonce ? { nonce } : {}) });
    if (error) throw toAuthAppError(error, "password");
  }

  async function requestReauthentication() {
    const { error } = await supabase.auth.reauthenticate();
    if (error) throw toAuthAppError(error, "email");
  }

  async function signOut(destination: "/" | "/login" = "/") {
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
      await router.replace(destination);
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
    resendConfirmation,
    requestPasswordReset,
    updatePassword,
    requestReauthentication,
    signOut,
    signingOut,
  };
}

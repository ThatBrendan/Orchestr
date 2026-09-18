<script setup lang="ts">
import { PASSWORD_MIN_LENGTH, PASSWORD_HINT, passwordError } from "@/lib/authPolicy";
import { trackProductEvent } from "@/lib/analytics";
import { ref } from "vue";
import { RouterLink, useRoute, useRouter } from "vue-router";
import { useAuth } from "@/composables/useAuth";
import { useToast } from "@/composables/useToast";
import { safeRedirect } from "@/router/guards";
import { toAuthAppError } from "@/lib/errors";
import { APP_NAME } from "@/config";
import orchestrioIcon from "@/assets/orchestrio-icon.svg";
import AppButton from "@/components/ui/AppButton.vue";

const route = useRoute();
const router = useRouter();
const { signUpWithPassword, resendConfirmation } = useAuth();
const toast = useToast();

const email = ref("");
const password = ref("");
const confirmation = ref("");
const resendBusy = ref(false);
const resendMessage = ref("");
const busy = ref(false);
let signupStarted = false;
const outcome = ref<null | "confirm">(null);

const dest = () => safeRedirect(route.query.redirect) ?? "/app";
const loginTo = { name: "login", query: route.query.redirect ? { redirect: String(route.query.redirect) } : undefined };

async function submit() {
  if (busy.value || !email.value.trim()) return;
  busy.value = true;
  try {
    const redirectPath = safeRedirect(route.query.redirect);
    const validation = passwordError(password.value, confirmation.value);
    if (validation) {
      toast.error(validation);
      return;
    }
    if (!signupStarted) {
      trackProductEvent("signup_started");
      signupStarted = true;
    }
    const { needsConfirmation } = await signUpWithPassword(email.value.trim(), password.value, redirectPath);
    // Release the keyboard before replacing the form or navigating onward.
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    if (needsConfirmation) {
      // NOT signed in — Supabase requires email confirmation.
      email.value = email.value.trim();
      password.value = "";
      confirmation.value = "";
      outcome.value = "confirm";
    } else {
      await router.push(dest());
    }
  } catch (e) {
    toast.error(toAuthAppError(e).message);
  } finally {
    busy.value = false;
  }
}
async function resend() {
  if (resendBusy.value) return;
  resendBusy.value = true;
  resendMessage.value = "";
  try {
    await resendConfirmation(email.value, safeRedirect(route.query.redirect));
    resendMessage.value = "Confirmation email sent.";
  } catch (e) { resendMessage.value = toAuthAppError(e).message; }
  finally { resendBusy.value = false; }
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center px-6 py-10 bg-paper">
    <div class="w-full max-w-sm fade-in">
      <RouterLink
        :to="{ name: 'landing' }"
        class="block text-center focus-ring"
        :aria-label="APP_NAME"
      >
        <img
          :src="orchestrioIcon"
          :alt="APP_NAME"
          class="mx-auto h-12 w-auto"
        >
      </RouterLink>
      <h1 class="mt-6 text-center font-display text-[19px] font-semibold tracking-tight">
        {{ outcome === "confirm" ? "Check your email" : "Create your account" }}
      </h1>

      <div
        v-if="outcome === 'confirm'"
        class="mt-6 border rounded-xl p-6 text-center border-line bg-surface"
      >
        <p class="text-14 text-ink-soft break-words">
          We sent a confirmation link to <span class="font-medium text-ink">{{ email }}</span>.
          Confirm your email to finish creating your Orchestrio account.
        </p>
        <AppButton
          class="mt-4"
          block
          :loading="resendBusy"
          @click="resend"
        >
          Resend confirmation email
        </AppButton>
        <p
          v-if="resendMessage"
          class="mt-3 text-13"
          role="status"
        >
          {{ resendMessage }}
        </p>
      </div>

      <form
        v-else
        class="mt-6 space-y-4"
        @submit.prevent="submit"
      >
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Email</span>
          <input
            v-model="email"
            type="email"
            required
            autocomplete="email"
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          >
        </label>

        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Password</span>
          <input
            v-model="password"
            type="password"
            required
            :minlength="PASSWORD_MIN_LENGTH"
            autocomplete="new-password"
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          >
          <span class="text-13 text-muted mt-1 block">{{ PASSWORD_HINT }}</span>
        </label>

        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Confirm password</span>
          <input
            v-model="confirmation"
            type="password"
            required
            autocomplete="new-password"
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          >
        </label>

        <AppButton
          type="submit"
          :loading="busy"
          block
        >
          Create account
        </AppButton>
      </form>

      <p class="mt-6 text-center text-13 text-muted">
        Already have an account?
        <RouterLink
          :to="loginTo"
          class="text-brand-dark font-medium focus-ring"
        >
          {{ outcome === "confirm" ? "Back to log in" : "Log in" }}
        </RouterLink>
      </p>
    </div>
  </div>
</template>

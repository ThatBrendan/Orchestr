<script setup lang="ts">
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
const { signInWithPassword, resendConfirmation } = useAuth();
const toast = useToast();

const email = ref("");
const password = ref("");
const busy = ref(false);
const unconfirmedEmail = ref("");
const resendBusy = ref(false);
const resendMessage = ref("");

const dest = () => safeRedirect(route.query.redirect) ?? "/app";
const signupTo = { name: "signup", query: route.query.redirect ? { redirect: String(route.query.redirect) } : undefined };

async function submit() {
  if (busy.value || !email.value.trim() || !password.value) return;
  busy.value = true;
  try {
    await signInWithPassword(email.value.trim(), password.value);
    // Release the keyboard before rendering the authenticated route.
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    await router.push(dest());
  } catch (e) {
    const failure = toAuthAppError(e);
    if (failure.code === "email_not_confirmed") unconfirmedEmail.value = email.value.trim();
    toast.error(failure.message);
  } finally {
    busy.value = false;
  }
}
async function resend() {
  if (resendBusy.value || !unconfirmedEmail.value) return;
  resendBusy.value = true;
  resendMessage.value = "";
  try {
    await resendConfirmation(unconfirmedEmail.value, safeRedirect(route.query.redirect));
    resendMessage.value = "Confirmation email sent.";
  } catch (e) { resendMessage.value = toAuthAppError(e, "email").message; }
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
        Log in
      </h1>

      <form
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
            autocomplete="current-password"
            required
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          >
        </label>

        <RouterLink
          :to="{ name: 'forgot-password' }"
          class="block text-right text-13 text-brand-dark focus-ring"
        >
          Forgot password?
        </RouterLink>

        <AppButton
          type="submit"
          :loading="busy"
          block
        >
          Log in
        </AppButton>
      </form>

      <div
        v-if="unconfirmedEmail"
        class="mt-4"
      >
        <AppButton
          variant="secondary"
          block
          :loading="resendBusy"
          @click="resend"
        >
          Resend confirmation email
        </AppButton>
        <p
          v-if="resendMessage"
          role="status"
          class="mt-3 text-13"
        >
          {{ resendMessage }}
        </p>
      </div>

      <p class="mt-6 text-center text-13 text-muted">
        Don't have an account?
        <RouterLink
          :to="signupTo"
          class="text-brand-dark font-medium focus-ring"
        >
          Sign up
        </RouterLink>
      </p>
    </div>
  </div>
</template>

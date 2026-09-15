<script setup lang="ts">
import { ref } from "vue";
import { useAuth } from "@/composables/useAuth";
import { RECOVERY_SENT } from "@/lib/authPolicy";
import { toAuthAppError } from "@/lib/errors";
import AuthPage from "@/components/ui/AuthPage.vue";
import AppButton from "@/components/ui/AppButton.vue";
const { requestPasswordReset } = useAuth();
const email = ref("");
const busy = ref(false);
const sent = ref(false);
const error = ref("");
async function submit() {
  if (busy.value || !email.value.trim()) return;
  busy.value = true;
  error.value = "";
  try {
    await requestPasswordReset(email.value.trim());
    sent.value = true;
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
  } catch (e) { error.value = toAuthAppError(e, "email").message; }
  finally { busy.value = false; }
}
</script>

<template>
  <AuthPage title="Forgot password?">
    <p
      v-if="sent"
      role="status"
      class="text-14 text-ink-soft"
    >
      {{ RECOVERY_SENT }}
    </p>
    <form
      v-else
      class="space-y-4"
      @submit.prevent="submit"
    >
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Email</span>
        <input
          v-model="email"
          type="email"
          required
          autocomplete="email"
          class="w-full border rounded-lg px-3.5 py-2.5 text-base focus-ring border-line bg-surface"
        >
      </label>
      <p
        v-if="error"
        role="alert"
        class="text-13 text-danger"
      >
        {{ error }}
      </p>
      <AppButton
        type="submit"
        :loading="busy"
        block
      >
        Send reset link
      </AppButton>
    </form>
    <RouterLink
      to="/login"
      class="block mt-6 text-center text-13 text-accent focus-ring"
    >
      Back to log in
    </RouterLink>
  </AuthPage>
</template>

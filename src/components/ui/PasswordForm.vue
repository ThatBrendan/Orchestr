<script setup lang="ts">
import { ref } from "vue";
import { useAuth } from "@/composables/useAuth";
import { PASSWORD_MIN_LENGTH, PASSWORD_HINT, passwordError } from "@/lib/authPolicy";
import { toAuthAppError } from "@/lib/errors";
import AppButton from "./AppButton.vue";
const props = defineProps<{ label: string; disabled?: boolean }>();
const emit = defineEmits<{ updated: [] }>();
const { updatePassword, requestReauthentication } = useAuth();
const password = ref("");
const confirmation = ref("");
const nonce = ref("");
const needsNonce = ref(false);
const busy = ref(false);
const message = ref("");
const error = ref("");
async function sendCode() {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try { await requestReauthentication(); message.value = "Check your email for a verification code."; }
  catch (e) { error.value = toAuthAppError(e, "password").message; }
  finally { busy.value = false; }
}
async function submit() {
  if (busy.value || props.disabled) return;
  error.value = passwordError(password.value, confirmation.value) ?? "";
  if (error.value) return;
  busy.value = true;
  message.value = "";
  try {
    await updatePassword(password.value, confirmation.value, nonce.value.trim() || undefined);
    password.value = confirmation.value = nonce.value = "";
    needsNonce.value = false;
    message.value = "Password updated successfully.";
    emit("updated");
  } catch (e) {
    const failure = toAuthAppError(e, "password");
    if (["reauthentication_needed", "reauthentication_not_valid"].includes(failure.code ?? "")) needsNonce.value = true;
    error.value = failure.message;
  } finally { busy.value = false; }
}
</script>

<template>
  <form
    class="space-y-4"
    @submit.prevent="submit"
  >
    <label class="block">
      <span class="text-13 font-medium block mb-1.5 text-ink-soft">New password</span>
      <input
        v-model="password"
        type="password"
        required
        :minlength="PASSWORD_MIN_LENGTH"
        autocomplete="new-password"
        :disabled="disabled || busy"
        class="w-full border rounded-lg px-3.5 py-2.5 text-base focus-ring border-line bg-surface"
      >
      <span class="text-13 text-muted mt-1 block">{{ PASSWORD_HINT }}</span>
    </label>
    <label class="block">
      <span class="text-13 font-medium block mb-1.5 text-ink-soft">Confirm new password</span>
      <input
        v-model="confirmation"
        type="password"
        required
        autocomplete="new-password"
        :disabled="disabled || busy"
        class="w-full border rounded-lg px-3.5 py-2.5 text-base focus-ring border-line bg-surface"
      >
    </label>
    <template v-if="needsNonce">
      <AppButton
        variant="secondary"
        :disabled="busy"
        @click="sendCode"
      >
        Send verification code
      </AppButton>
      <label class="block">
        <span class="text-13 font-medium block mb-1.5">Email verification code</span>
        <input
          v-model="nonce"
          required
          autocomplete="one-time-code"
          inputmode="numeric"
          class="w-full border rounded-lg px-3.5 py-2.5 text-base focus-ring border-line bg-surface"
        >
      </label>
    </template>
    <p
      v-if="error"
      role="alert"
      class="text-13 text-danger"
    >
      {{ error }}
    </p>
    <p
      v-if="message"
      role="status"
      class="text-13 text-ink-soft"
    >
      {{ message }}
    </p>
    <AppButton
      type="submit"
      :loading="busy"
      :disabled="disabled"
      block
    >
      {{ label }}
    </AppButton>
  </form>
</template>

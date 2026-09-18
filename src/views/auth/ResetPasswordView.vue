<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { useAuth } from "@/composables/useAuth";
import { toAuthAppError } from "@/lib/errors";
import AuthPage from "@/components/ui/AuthPage.vue";
import PasswordForm from "@/components/ui/PasswordForm.vue";
import AppButton from "@/components/ui/AppButton.vue";
const auth = useAuthStore();
const route = useRoute();
const router = useRouter();
onMounted(() => {
  if (route.hash || Object.keys(route.query).length) void router.replace("/reset-password");
});
const { signOut } = useAuth();
const updated = ref(false);
const busy = ref(false);
const error = ref("");
async function leave() {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try { await signOut("/login"); }
  catch (e) { error.value = toAuthAppError(e).message; }
  finally { busy.value = false; }
}
</script>

<template>
  <AuthPage title="Reset password">
    <template v-if="updated">
      <p
        role="status"
        class="text-14"
      >
        Password updated successfully.
      </p>
      <AppButton
        class="mt-4"
        block
        :loading="busy"
        @click="leave"
      >
        Continue to log in
      </AppButton>
    </template>
    <template v-else-if="auth.ready && auth.isAuthenticated && auth.recovery && !auth.linkError">
      <PasswordForm
        label="Update password"
        @updated="updated = true"
      />
      <AppButton
        class="mt-4"
        variant="secondary"
        block
        :loading="busy"
        @click="leave"
      >
        Cancel and log out
      </AppButton>
    </template>
    <template v-else-if="auth.ready">
      <p
        role="alert"
        class="text-14 text-ink-soft"
      >
        This password reset link is invalid or expired.
      </p>
      <AppButton
        v-if="auth.recovery"
        class="mt-4"
        block
        :loading="busy"
        @click="leave"
      >
        Back to log in
      </AppButton>
      <RouterLink
        v-else
        to="/forgot-password"
        class="block mt-4 text-brand-dark focus-ring"
      >
        Request a new reset link
      </RouterLink>
    </template>
    <p
      v-else
      role="status"
    >
      Checking your reset link…
    </p>
    <p
      v-if="error"
      role="alert"
      class="mt-4 text-13 text-danger"
    >
      {{ error }}
    </p>
  </AuthPage>
</template>

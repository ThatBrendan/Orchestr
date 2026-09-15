<script setup lang="ts">
import { watch, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { safeRedirect } from "@/lib/authPolicy";
import { initialAuthLink } from "@/lib/supabase";
import { trackProductEvent } from "@/lib/analytics";
import AuthPage from "@/components/ui/AuthPage.vue";
const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const failed = ref(false);
let resolved = false;
watch(() => auth.ready, (ready) => {
  if (!ready || resolved) return;
  resolved = true;
  const recovery = auth.recovery || initialAuthLink.recovery;
  if (auth.linkError || !auth.isAuthenticated) {
    failed.value = true;
    // Remove spent codes/error details; preserve only the validated invitation destination.
    const redirect = safeRedirect(route.query.redirect);
    void router.replace({ name: "auth.callback", query: redirect ? { redirect } : {} });
    return;
  }
  if (recovery) { void router.replace("/reset-password"); return; }
  if (initialAuthLink.isLink && initialAuthLink.signup) trackProductEvent("signup_completed");
  void router.replace(safeRedirect(route.query.redirect) ?? "/app");
}, { immediate: true });
</script>

<template>
  <AuthPage :title="failed ? 'Unable to confirm link' : 'Finishing sign in'">
    <template v-if="failed">
      <p
        role="alert"
        class="text-14 text-ink-soft"
      >
        {{ initialAuthLink.recovery ? 'This password reset link is invalid or expired.' : 'This confirmation link is invalid or expired. Request a new email and open it in the browser where you started.' }}
      </p>
      <RouterLink
        v-if="initialAuthLink.recovery"
        to="/forgot-password"
        class="block mt-4 text-accent focus-ring"
      >
        Request a new reset link
      </RouterLink>
      <RouterLink
        :to="{ name: 'login', query: safeRedirect(route.query.redirect) ? { redirect: safeRedirect(route.query.redirect) } : {} }"
        class="block mt-4 text-accent focus-ring"
      >
        Back to log in
      </RouterLink>
    </template>
    <p
      v-else
      role="status"
      class="text-center text-14"
    >
      Resolving your session…
    </p>
  </AuthPage>
</template>

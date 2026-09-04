<script setup lang="ts">
import { ref } from "vue";
import { RouterLink, useRoute, useRouter } from "vue-router";
import { useAuth } from "@/composables/useAuth";
import { useToast } from "@/composables/useToast";
import { usePageMeta } from "@/composables/usePageMeta";
import { safeRedirect } from "@/router/guards";
import { toAppError } from "@/lib/errors";
import { APP_NAME } from "@/config";
import AppButton from "@/components/ui/AppButton.vue";

usePageMeta({
  title: `Get started · ${APP_NAME}`,
  description: "Create an Orchestr account and start turning plans into coordinated execution.",
});

const route = useRoute();
const router = useRouter();
const { signUpWithPassword, signInWithOtp } = useAuth();
const toast = useToast();

const email = ref("");
const password = ref("");
const useMagicLink = ref(false);
const busy = ref(false);
const outcome = ref<null | "confirm" | "link">(null);

const dest = () => safeRedirect(route.query.redirect) ?? "/app";
const loginTo = { name: "login", query: route.query.redirect ? { redirect: String(route.query.redirect) } : undefined };

async function submit() {
  if (!email.value) return;
  busy.value = true;
  try {
    const redirectPath = safeRedirect(route.query.redirect);
    if (useMagicLink.value) {
      await signInWithOtp(email.value.trim(), redirectPath);
      outcome.value = "link";
      return;
    }
    if (password.value.length < 8) {
      toast.error("Use a password of at least 8 characters.");
      return;
    }
    const { needsConfirmation } = await signUpWithPassword(email.value.trim(), password.value, redirectPath);
    if (needsConfirmation) {
      // NOT signed in — Supabase requires email confirmation.
      outcome.value = "confirm";
    } else {
      await router.push(dest());
    }
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center px-6 bg-paper">
    <div class="w-full max-w-sm fade-in">
      <RouterLink
        :to="{ name: 'landing' }"
        class="font-display font-semibold text-[20px] tracking-tight block text-center focus-ring"
      >
        {{ APP_NAME }}
      </RouterLink>
      <h1 class="mt-6 text-center font-display text-[19px] font-semibold tracking-tight">Create your account</h1>

      <div v-if="outcome === 'confirm'" class="mt-6 border rounded-xl p-6 text-center border-line bg-surface">
        <p class="text-14 text-ink-soft">
          Almost there — check <span class="font-medium text-ink">{{ email }}</span> and confirm your email address to
          finish signing up.
        </p>
        <p class="mt-3 text-13 text-muted">You're not signed in yet.</p>
      </div>

      <div v-else-if="outcome === 'link'" class="mt-6 border rounded-xl p-6 text-center border-line bg-surface">
        <p class="text-14 text-ink-soft">
          Check <span class="font-medium text-ink">{{ email }}</span> for a link to finish signing up.
        </p>
        <button class="mt-3 text-13 text-accent font-medium focus-ring" @click="outcome = null">
          Use a different email
        </button>
      </div>

      <form v-else class="mt-6 space-y-4" @submit.prevent="submit">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Email</span>
          <input
            v-model="email"
            type="email"
            required
            autocomplete="email"
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          />
        </label>

        <label v-if="!useMagicLink" class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Password</span>
          <input
            v-model="password"
            type="password"
            required
            minlength="8"
            autocomplete="new-password"
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          />
          <span class="text-13 text-muted mt-1 block">At least 8 characters.</span>
        </label>

        <AppButton type="submit" :loading="busy" block>
          {{ useMagicLink ? "Send sign-up link" : "Create account" }}
        </AppButton>

        <button
          type="button"
          class="w-full text-13 text-muted hover:text-ink-soft focus-ring"
          @click="useMagicLink = !useMagicLink"
        >
          {{ useMagicLink ? "Use a password instead" : "Email me a link instead" }}
        </button>
      </form>

      <p class="mt-6 text-center text-13 text-muted">
        Already have an account?
        <RouterLink :to="loginTo" class="text-accent font-medium focus-ring">Log in</RouterLink>
      </p>
    </div>
  </div>
</template>

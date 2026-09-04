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

usePageMeta({ title: `Log in · ${APP_NAME}`, description: "Log in to your Orchestr workspace." });

const route = useRoute();
const router = useRouter();
const { signInWithOtp, signInWithPassword } = useAuth();
const toast = useToast();

const email = ref("");
const password = ref("");
const usePassword = ref(false);
const busy = ref(false);
const linkSent = ref(false);

const dest = () => safeRedirect(route.query.redirect) ?? "/app";
const signupTo = { name: "signup", query: route.query.redirect ? { redirect: String(route.query.redirect) } : undefined };

async function submit() {
  if (!email.value) return;
  busy.value = true;
  try {
    if (usePassword.value) {
      await signInWithPassword(email.value.trim(), password.value);
      await router.push(dest());
    } else {
      await signInWithOtp(email.value.trim(), safeRedirect(route.query.redirect));
      linkSent.value = true;
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
      <h1 class="mt-6 text-center font-display text-[19px] font-semibold tracking-tight">Log in</h1>

      <div v-if="linkSent" class="mt-6 border rounded-xl p-6 text-center border-line bg-surface">
        <p class="text-14 text-ink-soft">
          Check <span class="font-medium text-ink">{{ email }}</span> for a sign-in link.
        </p>
        <button class="mt-3 text-13 text-accent font-medium focus-ring" @click="linkSent = false">
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

        <label v-if="usePassword" class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Password</span>
          <input
            v-model="password"
            type="password"
            autocomplete="current-password"
            required
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          />
        </label>

        <AppButton type="submit" :loading="busy" block>
          {{ usePassword ? "Log in" : "Send sign-in link" }}
        </AppButton>

        <button
          type="button"
          class="w-full text-13 text-muted hover:text-ink-soft focus-ring"
          @click="usePassword = !usePassword"
        >
          {{ usePassword ? "Email me a link instead" : "Log in with a password" }}
        </button>
      </form>

      <p class="mt-6 text-center text-13 text-muted">
        Don't have an account?
        <RouterLink :to="signupTo" class="text-accent font-medium focus-ring">Sign up</RouterLink>
      </p>
    </div>
  </div>
</template>

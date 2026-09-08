<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { useAuth } from "@/composables/useAuth";
import AppButton from "@/components/ui/AppButton.vue";

const { isAuthenticated } = useAuth();
const primary = computed(() =>
  isAuthenticated.value
    ? { to: { name: "dashboard" }, label: "Open Orchestrio" }
    : { to: { name: "signup" }, label: "Create your first plan" },
);
</script>

<template>
  <section class="max-w-6xl mx-auto px-5 md:px-8 py-20 md:py-28 text-center" aria-labelledby="cta-heading">
    <h2 id="cta-heading" class="font-display text-[28px] md:text-[38px] font-semibold tracking-tight">
      Keep the whole plan moving.
    </h2>
    <p class="mt-4 text-[16px] text-ink-soft max-w-xl mx-auto">
      Bring the costs, owners, deadlines and progress into one place — and stop chasing the details.
    </p>
    <div class="mt-8 flex flex-col sm:flex-row items-center justify-center gap-3">
      <AppButton :to="primary.to" size="lg">{{ primary.label }}</AppButton>
    </div>
    <p v-if="!isAuthenticated" class="mt-4 text-13 text-muted">
      Already have an account?
      <RouterLink :to="{ name: 'login' }" class="text-accent font-medium focus-ring">Log in</RouterLink>
    </p>
  </section>
</template>

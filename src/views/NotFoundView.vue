<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { APP_NAME } from "@/config";
import { useAuth } from "@/composables/useAuth";
import AppButton from "@/components/ui/AppButton.vue";

const { isAuthenticated } = useAuth();
const backTo = computed(() => (isAuthenticated.value ? { name: "dashboard" } : { name: "landing" }));
</script>

<template>
  <div class="min-h-screen flex items-center justify-center px-6 bg-paper">
    <div class="text-center">
      <RouterLink
        :to="{ name: 'landing' }"
        class="font-display font-semibold text-[17px] focus-ring"
      >
        {{ APP_NAME }}
      </RouterLink>
      <h1 class="mt-6 font-display text-3xl font-semibold">
        Page not found
      </h1>
      <p class="mt-3 text-14 text-ink-soft">
        The page you’re looking for doesn’t exist or may have moved.
      </p>
      <div class="mt-5 flex flex-wrap gap-3 justify-center">
        <AppButton
          variant="secondary"
          size="sm"
          :to="{ name: 'landing' }"
        >
          Go home
        </AppButton>
        <AppButton
          :to="isAuthenticated ? backTo : { name: 'login' }"
          size="sm"
        >
          {{ isAuthenticated ? "Dashboard" : "Log in" }}
        </AppButton>
      </div>
    </div>
  </div>
</template>

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
      <RouterLink :to="{ name: 'landing' }" class="font-display font-semibold text-[17px] focus-ring">
        {{ APP_NAME }}
      </RouterLink>
      <p class="mt-3 text-14 text-ink-soft">That page doesn't exist, or you don't have access to it.</p>
      <div class="mt-5 flex justify-center">
        <AppButton variant="secondary" size="sm" :to="backTo">
          {{ isAuthenticated ? "Back to dashboard" : "Back to home" }}
        </AppButton>
      </div>
    </div>
  </div>
</template>

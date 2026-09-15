<script setup lang="ts">
import { APP_NAME } from "@/config";
import orchestrioIcon from "@/assets/orchestrio-icon.svg";
defineProps<{ title: string }>();
</script>

<template>
  <div class="min-h-screen flex items-center justify-center px-6 py-10 bg-paper">
    <div class="w-full min-w-0 max-w-sm fade-in">
      <RouterLink
        to="/"
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
        {{ title }}
      </h1>
      <div class="mt-6">
        <slot />
      </div>
    </div>
  </div>
</template>

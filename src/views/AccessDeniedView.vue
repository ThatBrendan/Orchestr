<script setup lang="ts">
import AppButton from "@/components/ui/AppButton.vue";
</script>

<template>
  <main class="min-h-screen grid place-items-center px-6 bg-canvas">
    <div class="max-w-md text-center">
      <p class="text-13 font-medium uppercase text-muted">Access denied</p>
      <h1 class="mt-3 font-display text-[30px] font-semibold tracking-tight text-ink">
        This area is for platform admins.
      </h1>
      <p class="mt-3 text-14.5 text-ink-soft">
        Your Orchestrio projects are still available in the main application.
      </p>
      <div class="mt-6 flex justify-center">
        <AppButton :to="{ name: 'dashboard' }">Open Orchestrio</AppButton>
      </div>
    </div>
  </main>
</template>

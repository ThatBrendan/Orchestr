<script setup lang="ts">
import { RouterView } from "vue-router";
import ToastHost from "@/components/ui/ToastHost.vue";
import AppErrorBoundary from "@/components/ui/AppErrorBoundary.vue";
import PwaExperience from "@/components/pwa/PwaExperience.vue";
</script>

<template>
  <AppErrorBoundary>
    <RouterView />
  </AppErrorBoundary>
  <ToastHost />
  <PwaExperience />
</template>

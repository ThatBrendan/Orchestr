<script setup lang="ts">
import { RouterView } from "vue-router";
import ToastHost from "@/components/ui/ToastHost.vue";
import AppErrorBoundary from "@/components/ui/AppErrorBoundary.vue";
</script>

<template>
  <AppErrorBoundary>
    <RouterView />
  </AppErrorBoundary>
  <ToastHost />
</template>

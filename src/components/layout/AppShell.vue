<script setup lang="ts">
import { RouterView } from "vue-router";
import AppSidebar from "./AppSidebar.vue";
import AppBottomNav from "./AppBottomNav.vue";
import AppTopBar from "./AppTopBar.vue";
</script>

<template>
  <div class="flex min-h-screen">
    <AppSidebar />
    <div class="flex-1 min-w-0 flex flex-col">
      <AppTopBar />
      <main class="flex-1 min-w-0 pb-24 md:pb-0">
        <RouterView />
      </main>
    </div>
    <AppBottomNav />
  </div>
</template>

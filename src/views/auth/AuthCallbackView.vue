<script setup lang="ts">
import { onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { storeToRefs } from "pinia";
import { watch } from "vue";
import { useAuthStore } from "@/stores/auth";
import { safeRedirect } from "@/router/guards";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const { ready, isAuthenticated } = storeToRefs(auth);

function resolve() {
  if (!ready.value) return;
  const redirect = safeRedirect(route.query.redirect) ?? "/app";
  void router.replace(isAuthenticated.value ? redirect : { name: "login" });
}

onMounted(resolve);
watch(ready, resolve);
</script>

<template>
  <div class="min-h-screen flex items-center justify-center bg-paper">
    <span class="inline-block w-5 h-5 rounded-full border-2 border-ink-soft border-r-transparent animate-spin" />
  </div>
</template>

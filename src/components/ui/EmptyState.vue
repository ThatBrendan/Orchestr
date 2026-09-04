<script setup lang="ts">
defineProps<{ title?: string; message: string }>();
</script>

<template>
  <div class="border rounded-xl p-10 text-center border-line">
    <p v-if="title" class="text-14 font-medium text-ink">{{ title }}</p>
    <p class="text-14 text-muted" :class="{ 'mt-1': title }">{{ message }}</p>
    <div class="mt-4 flex justify-center"><slot name="action" /></div>
  </div>
</template>

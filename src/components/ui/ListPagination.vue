<script setup lang="ts">
import AppButton from './AppButton.vue';
defineProps<{ page: number; previous: boolean; next: boolean; label: string; busy?: boolean }>();
defineEmits<{ 'update:page': [value: number] }>();
</script>
<template>
  <nav
    v-if="previous || next"
    :aria-label="label"
    class="mt-3 flex flex-wrap justify-between gap-3"
  >
    <AppButton
      v-if="previous"
      size="sm"
      variant="secondary"
      :disabled="busy"
      @click="$emit('update:page', page - 1)"
    >
      Previous
    </AppButton>
    <AppButton
      v-if="next"
      size="sm"
      variant="secondary"
      class="ml-auto"
      :disabled="busy"
      @click="$emit('update:page', page + 1)"
    >
      Next
    </AppButton>
  </nav>
</template>

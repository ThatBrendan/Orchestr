<script setup lang="ts">
import { computed } from "vue";
import { toAppError } from "@/lib/errors";
import AppButton from "./AppButton.vue";

const props = defineProps<{ error: unknown; retry?: () => void }>();

const message = computed(() => {
  const e = toAppError(props.error);
  if (e.kind === "permission") return "You don't have access to this.";
  if (e.kind === "network") return "Network problem — check your connection.";
  return e.message || "Something went wrong.";
});
</script>

<template>
  <div class="border rounded-xl p-8 text-center border-line bg-surface">
    <p class="text-14 text-ink-soft">
      {{ message }}
    </p>
    <div
      v-if="props.retry"
      class="mt-4 flex justify-center"
    >
      <AppButton
        variant="secondary"
        size="sm"
        @click="props.retry"
      >
        Try again
      </AppButton>
    </div>
  </div>
</template>

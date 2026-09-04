<script setup lang="ts">
import { ref, onErrorCaptured } from "vue";
import { logger } from "@/lib/logger";
import { toAppError } from "@/lib/errors";
import AppButton from "./AppButton.vue";
import { APP_NAME } from "@/config";

const crashed = ref<string | null>(null);

onErrorCaptured((err) => {
  const e = toAppError(err);
  logger.error("render error captured", { kind: e.kind, code: e.code });
  crashed.value = e.message;
  return false;
});

function reload() {
  window.location.reload();
}
</script>

<template>
  <div v-if="crashed" class="min-h-screen flex items-center justify-center p-6 bg-paper">
    <div class="max-w-sm text-center">
      <div class="font-display font-semibold text-[17px]">{{ APP_NAME }}</div>
      <p class="mt-3 text-14 text-ink-soft">Something went wrong on this screen.</p>
      <p class="mt-1 text-13 text-muted">{{ crashed }}</p>
      <div class="mt-5 flex justify-center">
        <AppButton variant="secondary" size="sm" @click="reload">Reload</AppButton>
      </div>
    </div>
  </div>
  <slot v-else />
</template>

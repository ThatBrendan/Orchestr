<script setup lang="ts">
import { storeToRefs } from "pinia";
import { useUiStore } from "@/stores/ui";
import AppIcon from "./AppIcon.vue";

const ui = useUiStore();
const { toasts } = storeToRefs(ui);
</script>

<template>
  <div class="fixed bottom-4 right-4 z-50 flex flex-col gap-2 w-[320px] max-w-[calc(100vw-2rem)]">
    <TransitionGroup name="toast">
      <div
        v-for="t in toasts"
        :key="t.id"
        class="rounded-lg border shadow-sm px-4 py-3 text-14 flex items-start gap-2 bg-surface"
        :class="{
          'border-danger-soft': t.kind === 'error',
          'border-accent-soft': t.kind === 'success',
          'border-line': t.kind === 'info',
        }"
      >
        <span
          class="mt-0.5"
          :class="{
            'text-danger': t.kind === 'error',
            'text-accent': t.kind === 'success',
            'text-muted': t.kind === 'info',
          }"
        >
          <AppIcon :name="t.kind === 'success' ? 'check' : 'alert'" :size="15" />
        </span>
        <span class="flex-1 text-ink-soft">{{ t.message }}</span>
        <button class="text-muted hover:text-ink" @click="ui.dismissToast(t.id)">
          <AppIcon name="close" :size="14" />
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition: all 0.2s ease;
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateY(6px);
}
</style>

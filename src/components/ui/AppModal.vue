<script setup lang="ts">
import { computed } from "vue";
import { Dialog, DialogPanel, DialogTitle, TransitionRoot, TransitionChild } from "@headlessui/vue";
import AppIcon from "./AppIcon.vue";

const props = withDefaults(defineProps<{ open: boolean; title: string; size?: "md" | "lg"; busy?: boolean }>(), {
  size: "md",
});
const emit = defineEmits<{ close: [] }>();

const widthClass = computed(() => (props.size === "lg" ? "max-w-2xl" : "max-w-md"));
</script>

<template>
  <TransitionRoot :show="props.open" as="template">
    <Dialog class="relative z-40" @close="!props.busy && emit('close')">
      <TransitionChild
        as="template"
        enter="duration-150 ease-out"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="duration-100 ease-in"
        leave-from="opacity-100"
        leave-to="opacity-0"
      >
        <div class="fixed inset-0" style="background: rgba(20, 20, 18, 0.4)" />
      </TransitionChild>

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <TransitionChild
          as="template"
          enter="duration-150 ease-out"
          enter-from="opacity-0 translate-y-1"
          enter-to="opacity-100 translate-y-0"
        >
          <DialogPanel
            class="w-full rounded-2xl overflow-hidden bg-surface max-h-[85vh] flex flex-col"
            :class="widthClass"
          >
            <div class="px-6 pt-5 pb-4 border-b border-line flex items-center justify-between shrink-0">
              <DialogTitle class="font-display text-[17px] font-semibold">{{ props.title }}</DialogTitle>
              <button :disabled="props.busy" class="text-ink-soft hover:text-ink" @click="!props.busy && emit('close')">
                <AppIcon name="close" :size="18" />
              </button>
            </div>
            <div class="px-6 py-5 overflow-y-auto"><slot /></div>
            <div v-if="$slots.footer" class="px-6 py-4 border-t border-line flex justify-end gap-2 shrink-0">
              <slot name="footer" />
            </div>
          </DialogPanel>
        </TransitionChild>
      </div>
    </Dialog>
  </TransitionRoot>
</template>

<script setup lang="ts">
import { Dialog, DialogPanel, DialogTitle, TransitionRoot, TransitionChild } from "@headlessui/vue";
import AppIcon from "./AppIcon.vue";

const props = defineProps<{ open: boolean; title: string }>();
const emit = defineEmits<{ close: [] }>();
</script>

<template>
  <TransitionRoot :show="props.open" as="template">
    <Dialog class="relative z-40" @close="emit('close')">
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
          <DialogPanel class="w-full max-w-md rounded-2xl overflow-hidden bg-surface">
            <div class="px-6 pt-5 pb-4 border-b border-line flex items-center justify-between">
              <DialogTitle class="font-display text-[17px] font-semibold">{{ props.title }}</DialogTitle>
              <button class="text-ink-soft hover:text-ink" @click="emit('close')">
                <AppIcon name="close" :size="18" />
              </button>
            </div>
            <div class="px-6 py-5"><slot /></div>
            <div v-if="$slots.footer" class="px-6 py-4 border-t border-line flex justify-end gap-2">
              <slot name="footer" />
            </div>
          </DialogPanel>
        </TransitionChild>
      </div>
    </Dialog>
  </TransitionRoot>
</template>

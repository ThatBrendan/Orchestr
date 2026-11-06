<script setup lang="ts">
import { computed } from "vue";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { usePwaInstall } from "@/composables/usePwaInstall";
import { isIosSafari } from "@/lib/pwaInstall";

const pwa = usePwaInstall();
const otherIosBrowser = computed(() => {
  if (typeof navigator === "undefined") return false;
  return !isIosSafari(navigator.userAgent);
});
</script>

<template>
  <AppModal
    :open="pwa.instructionsOpen.value"
    title="Add Orchestrio to your Home Screen"
    @close="pwa.closeInstructions()"
  >
    <ol class="space-y-4 text-sm">
      <li class="flex gap-3">
        <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-ink text-xs font-semibold text-white">1</span>
        <span><strong>Open Orchestrio in Safari.</strong><span class="mt-1 block text-ink-soft">If you are using another iOS browser, open this page in Safari for the most reliable experience.</span></span>
      </li>
      <li class="flex gap-3">
        <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-ink text-xs font-semibold text-white">2</span>
        <span><strong>Tap the Share icon.</strong><span class="mt-1 block text-ink-soft">It is usually in the browser toolbar at the top or bottom of the screen.</span></span>
      </li>
      <li class="flex gap-3">
        <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-ink text-xs font-semibold text-white">3</span>
        <span><strong>Select Add to Home Screen.</strong></span>
      </li>
      <li class="flex gap-3">
        <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-ink text-xs font-semibold text-white">4</span>
        <span><strong>Confirm by tapping Add.</strong></span>
      </li>
    </ol>
    <p
      v-if="otherIosBrowser"
      class="mt-4 text-xs text-ink-soft"
    >
      Installation menus differ by browser. Safari may require an additional Copy link or Open in Safari step.
    </p>
    <template #footer>
      <AppButton
        size="sm"
        variant="secondary"
        @click="pwa.closeInstructions()"
      >
        Done
      </AppButton>
    </template>
  </AppModal>
</template>

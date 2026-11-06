<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import { config } from "@/config";
import { usePwaInstall } from "@/composables/usePwaInstall";
import PwaInstallInstructions from "@/components/pwa/PwaInstallInstructions.vue";

const online = ref(typeof navigator === "undefined" ? true : navigator.onLine);
const updateWorker = ref<ServiceWorker | null>(null);
let registration: ServiceWorkerRegistration | null = null;
let reloadAfterUpdate = false;
const pwa = usePwaInstall();

function onOnline() { online.value = true; }
function onOffline() { online.value = false; }
function onControllerChange() {
  if (reloadAfterUpdate) window.location.reload();
}
function watchRegistration(reg: ServiceWorkerRegistration) {
  registration = reg;
  if (reg.waiting && navigator.serviceWorker.controller) updateWorker.value = reg.waiting;
  reg.addEventListener("updatefound", () => {
    const installing = reg.installing;
    installing?.addEventListener("statechange", () => {
      if (installing.state === "installed" && navigator.serviceWorker.controller) updateWorker.value = installing;
    });
  });
}
async function refreshForUpdate() {
  const waiting = updateWorker.value ?? registration?.waiting;
  if (!waiting) return;
  reloadAfterUpdate = true;
  waiting.postMessage({ type: "SKIP_WAITING" });
}

onMounted(() => {
  online.value = navigator.onLine;
  pwa.initializePwaInstall();
  window.addEventListener("online", onOnline);
  window.addEventListener("offline", onOffline);
  navigator.serviceWorker?.addEventListener("controllerchange", onControllerChange);
  if ((config.env === "production" || config.env === "staging") && window.isSecureContext && "serviceWorker" in navigator) {
    void navigator.serviceWorker.register("/sw.js", { scope: "/" }).then(watchRegistration).catch(() => { /* The app remains online-first if SW registration is unavailable. */ });
  }
});

onUnmounted(() => {
  window.removeEventListener("online", onOnline);
  window.removeEventListener("offline", onOffline);
  navigator.serviceWorker?.removeEventListener("controllerchange", onControllerChange);
  pwa.destroyPwaInstall();
});
</script>

<template>
  <div
    class="pointer-events-none fixed inset-x-0 top-0 z-[60] flex justify-center px-3"
    aria-live="polite"
  >
    <p
      v-if="!online"
      class="pointer-events-auto rounded-b-lg bg-ink px-4 py-2 text-center text-sm text-white shadow-lg"
    >
      You’re offline. Project data may be out of date; changes need a connection and won’t save offline.
    </p>
  </div>
  <aside
    v-if="updateWorker"
    class="fixed bottom-4 right-4 z-[60] flex max-w-[calc(100vw-2rem)] flex-col items-end gap-2"
  >
    <button
      type="button"
      class="rounded-lg bg-surface px-3 py-2 text-sm font-semibold shadow-lg ring-1 ring-line"
      @click="refreshForUpdate"
    >
      Update ready · Refresh
    </button>
  </aside>
  <PwaInstallInstructions />
</template>

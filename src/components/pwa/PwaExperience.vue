<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { config } from "@/config";

type InstallPromptEvent = Event & { prompt: () => Promise<void>; userChoice: Promise<{ outcome: "accepted" | "dismissed" }> };
const online = ref(typeof navigator === "undefined" ? true : navigator.onLine);
const installPrompt = ref<InstallPromptEvent | null>(null);
const installInstructionsOpen = ref(false);
const installDismissed = ref(false);
const updateWorker = ref<ServiceWorker | null>(null);
const isInstalled = ref(false);
const ios = ref(false);
let registration: ServiceWorkerRegistration | null = null;
let reloadAfterUpdate = false;
const showInstall = computed(() => !isInstalled.value && !installDismissed.value && (Boolean(installPrompt.value) || ios.value));

function onOnline() { online.value = true; }
function onOffline() { online.value = false; }
function isStandalone() {
  return window.matchMedia("(display-mode: standalone)").matches || (navigator as Navigator & { standalone?: boolean }).standalone === true;
}
function dismissInstall() {
  installDismissed.value = true;
  try { localStorage.setItem("orchestrio-install-dismissed", "1"); } catch { /* Storage is optional. */ }
}
async function install() {
  if (!installPrompt.value) { installInstructionsOpen.value = !installInstructionsOpen.value; return; }
  const prompt = installPrompt.value;
  installPrompt.value = null;
  await prompt.prompt();
  const choice = await prompt.userChoice;
  if (choice.outcome === "dismissed") dismissInstall();
}
function onInstalled() {
  isInstalled.value = true;
  installPrompt.value = null;
  installInstructionsOpen.value = false;
  try { localStorage.setItem("orchestrio-installed", "1"); } catch { /* Storage is optional. */ }
}
function onBeforeInstallPrompt(event: Event) {
  event.preventDefault();
  if (!isInstalled.value && !installDismissed.value) installPrompt.value = event as InstallPromptEvent;
}
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
  isInstalled.value = isStandalone();
  ios.value = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  try {
    installDismissed.value = localStorage.getItem("orchestrio-install-dismissed") === "1";
    isInstalled.value ||= localStorage.getItem("orchestrio-installed") === "1" && isStandalone();
  } catch { /* Storage is optional. */ }
  window.addEventListener("online", onOnline);
  window.addEventListener("offline", onOffline);
  window.addEventListener("beforeinstallprompt", onBeforeInstallPrompt);
  window.addEventListener("appinstalled", onInstalled);
  navigator.serviceWorker?.addEventListener("controllerchange", onControllerChange);
  if ((config.env === "production" || config.env === "staging") && window.isSecureContext && "serviceWorker" in navigator) {
    void navigator.serviceWorker.register("/sw.js", { scope: "/" }).then(watchRegistration).catch(() => { /* The app remains online-first if SW registration is unavailable. */ });
  }
});

onUnmounted(() => {
  window.removeEventListener("online", onOnline);
  window.removeEventListener("offline", onOffline);
  window.removeEventListener("beforeinstallprompt", onBeforeInstallPrompt);
  window.removeEventListener("appinstalled", onInstalled);
  navigator.serviceWorker?.removeEventListener("controllerchange", onControllerChange);
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
    v-if="showInstall || updateWorker"
    class="fixed bottom-4 right-4 z-[60] flex max-w-[calc(100vw-2rem)] flex-col items-end gap-2"
  >
    <div
      v-if="installInstructionsOpen && ios && !installPrompt"
      class="w-72 rounded-xl border border-line bg-surface p-4 text-sm shadow-xl"
      role="status"
    >
      <p class="font-semibold">
        Add Orchestrio to your Home Screen
      </p>
      <p class="mt-2 leading-relaxed text-ink-soft">
        In Safari, tap Share, then choose “Add to Home Screen”.
      </p>
    </div>
    <div class="flex items-center gap-2">
      <button
        v-if="updateWorker"
        type="button"
        class="rounded-lg bg-surface px-3 py-2 text-sm font-semibold shadow-lg ring-1 ring-line"
        @click="refreshForUpdate"
      >
        Update ready · Refresh
      </button>
      <button
        v-if="showInstall"
        type="button"
        class="rounded-lg bg-ink px-3 py-2 text-sm font-semibold text-white shadow-lg"
        @click="install"
      >
        {{ installPrompt ? "Install Orchestrio" : "Add to Home Screen" }}
      </button>
      <button
        v-if="showInstall"
        type="button"
        class="rounded-lg bg-surface px-3 py-2 text-sm shadow-lg ring-1 ring-line"
        aria-label="Dismiss install option"
        @click="dismissInstall"
      >
        Dismiss
      </button>
    </div>
  </aside>
</template>

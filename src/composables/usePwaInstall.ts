import { computed, ref } from "vue";
import type { InstallPromptEvent } from "@/lib/pwaInstall";
import {
  isIosDevice,
  isStandaloneMode,
  readInstallDismissed,
  writeInstallDismissed,
} from "@/lib/pwaInstall";

const isInstalled = ref(false);
const isIos = ref(false);
const installPrompt = ref<InstallPromptEvent | null>(null);
const installDismissed = ref(false);
const instructionsOpen = ref(false);
const installing = ref(false);
let initialized = false;

const nativeAvailable = computed(() => !!installPrompt.value);
const canOfferDashboardCard = computed(() =>
  !isInstalled.value
  && !installDismissed.value
  && (nativeAvailable.value || isIos.value),
);

function initializePwaInstall() {
  if (initialized || typeof window === "undefined") return;
  initialized = true;
  isInstalled.value = isStandaloneMode(
    window.matchMedia("(display-mode: standalone)").matches,
    (navigator as Navigator & { standalone?: boolean }).standalone,
  );
  isIos.value = isIosDevice(navigator.userAgent, navigator.platform, navigator.maxTouchPoints);
  try {
    installDismissed.value = readInstallDismissed(window.localStorage);
  } catch {
    installDismissed.value = false;
  }

  window.addEventListener("beforeinstallprompt", onBeforeInstallPrompt);
  window.addEventListener("appinstalled", onAppInstalled);
}

function destroyPwaInstall() {
  if (!initialized || typeof window === "undefined") return;
  initialized = false;
  window.removeEventListener("beforeinstallprompt", onBeforeInstallPrompt);
  window.removeEventListener("appinstalled", onAppInstalled);
}

function onBeforeInstallPrompt(event: Event) {
  event.preventDefault();
  if (!isInstalled.value) installPrompt.value = event as InstallPromptEvent;
}

function onAppInstalled() {
  isInstalled.value = true;
  installPrompt.value = null;
  instructionsOpen.value = false;
  installing.value = false;
}

async function installOrchestrio() {
  if (isInstalled.value) return;
  if (isIos.value) {
    instructionsOpen.value = true;
    return;
  }
  const prompt = installPrompt.value;
  if (!prompt) return;

  installing.value = true;
  installPrompt.value = null;
  try {
    await prompt.prompt();
    const choice = await prompt.userChoice;
    if (choice.outcome === "dismissed") dismissInstall();
  } finally {
    installing.value = false;
  }
}

function dismissInstall() {
  installDismissed.value = true;
  instructionsOpen.value = false;
  try {
    writeInstallDismissed(typeof window !== "undefined" ? window.localStorage : null);
  } catch {
    // Dismissal state remains available for the current session.
  }
}

export function usePwaInstall() {
  return {
    isInstalled,
    isIos,
    nativeAvailable,
    installDismissed,
    canOfferDashboardCard,
    instructionsOpen,
    installing,
    initializePwaInstall,
    destroyPwaInstall,
    installOrchestrio,
    dismissInstall,
    openInstructions: () => { instructionsOpen.value = true; },
    closeInstructions: () => { instructionsOpen.value = false; },
  };
}

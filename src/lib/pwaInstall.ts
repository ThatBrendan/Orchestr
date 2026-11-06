export const PWA_INSTALL_DISMISSAL_KEY = "orchestrio-install-dismissed-v1";
export const PWA_INSTALL_DISMISSAL_MS = 30 * 24 * 60 * 60 * 1000;

export interface InstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

export function isStandaloneMode(displayModeStandalone: boolean, navigatorStandalone?: boolean): boolean {
  return displayModeStandalone || navigatorStandalone === true;
}

export function isIosDevice(userAgent: string, platform: string, maxTouchPoints: number): boolean {
  const iphoneIpadIpod = /iPad|iPhone|iPod/.test(userAgent);
  const ipadDesktopMode = platform === "MacIntel" && maxTouchPoints > 1;
  return iphoneIpadIpod || ipadDesktopMode;
}

export function isIosSafari(userAgent: string): boolean {
  return /Safari/.test(userAgent) && !/(CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo)/.test(userAgent);
}

export function readInstallDismissed(storage: Pick<Storage, "getItem"> | null, now = Date.now()): boolean {
  if (!storage) return false;
  try {
    const dismissedAt = Number(storage.getItem(PWA_INSTALL_DISMISSAL_KEY));
    return Number.isFinite(dismissedAt) && now - dismissedAt < PWA_INSTALL_DISMISSAL_MS;
  } catch {
    return false;
  }
}

export function writeInstallDismissed(storage: Pick<Storage, "setItem"> | null, now = Date.now()): void {
  if (!storage) return;
  try {
    storage.setItem(PWA_INSTALL_DISMISSAL_KEY, String(now));
  } catch {
    // Dismissal is optional when browser storage is unavailable.
  }
}

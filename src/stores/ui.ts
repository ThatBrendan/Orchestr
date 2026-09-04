import { defineStore } from "pinia";
import { ref } from "vue";

export interface Toast {
  id: number;
  kind: "success" | "error" | "info";
  message: string;
}

/** Ephemeral UI state (docs/TECHNICAL_ARCHITECTURE.md §4). */
export const useUiStore = defineStore("ui", () => {
  const toasts = ref<Toast[]>([]);
  let seq = 0;

  function pushToast(kind: Toast["kind"], message: string, ttl = 5000) {
    const id = ++seq;
    toasts.value.push({ id, kind, message });
    if (ttl > 0) window.setTimeout(() => dismissToast(id), ttl);
  }
  function dismissToast(id: number) {
    toasts.value = toasts.value.filter((t) => t.id !== id);
  }

  return { toasts, pushToast, dismissToast };
});

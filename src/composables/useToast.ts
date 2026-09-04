import { useUiStore } from "@/stores/ui";

export function useToast() {
  const ui = useUiStore();
  return {
    success: (m: string) => ui.pushToast("success", m),
    error: (m: string) => ui.pushToast("error", m),
    info: (m: string) => ui.pushToast("info", m),
  };
}

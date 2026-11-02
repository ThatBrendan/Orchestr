import { nextTick, watch, type Ref } from "vue";

/** Keep keyboard context in execution screens, including detail → edit transitions. */
export function useExecutionDialogFocus(open: Ref<boolean>, fallback: Ref<HTMLElement | null>) {
  let opener: HTMLElement | null = null;
  function restoreFocus() {
    if (open.value) return;
    void nextTick(() => requestAnimationFrame(() => {
      if (!open.value) (opener?.isConnected ? opener : fallback.value)?.focus({ preventScroll: true });
    }));
  }
  watch(open, (value, previous) => {
    if (value && !previous) opener = document.activeElement instanceof HTMLElement && document.activeElement !== document.body ? document.activeElement : null;
    else if (!value) restoreFocus();
  });
  return restoreFocus;
}

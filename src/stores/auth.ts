import { defineStore } from "pinia";
import { ref, computed } from "vue";
import type { Session, User } from "@supabase/supabase-js";

/** Session state only (docs/TECHNICAL_ARCHITECTURE.md §4). No domain data here. */
export const useAuthStore = defineStore("auth", () => {
  const session = ref<Session | null>(null);
  const user = ref<User | null>(null);
  const recovery = ref(false);
  const linkError = ref(false);
  const ready = ref(false); // true once the initial session has been resolved

  const isAuthenticated = computed(() => !!session.value);
  const userId = computed(() => user.value?.id ?? null);
  const email = computed(() => user.value?.email ?? null);

  function setSession(s: Session | null) {
    session.value = s;
    user.value = s?.user ?? null;
  }

  function setRecovery(value: boolean) {
    recovery.value = value;
    try {
      if (value && user.value) sessionStorage.setItem("orchestrio-recovery-user", user.value.id);
      else sessionStorage.removeItem("orchestrio-recovery-user");
    } catch { /* Recovery still works when browser storage is unavailable. */ }
  }

  function restoreRecovery() {
    try { recovery.value = !!user.value && sessionStorage.getItem("orchestrio-recovery-user") === user.value.id; }
    catch { /* In-memory state remains authoritative. */ }
  }

  function markReady() {
    ready.value = true;
  }

  function reset() {
    setRecovery(false);
    session.value = null;
    user.value = null;
  }

  return { recovery, linkError, setRecovery, restoreRecovery, session, user, ready, isAuthenticated, userId, email, setSession, markReady, reset };
});

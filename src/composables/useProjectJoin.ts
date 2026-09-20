import { ref, watch, toValue, onScopeDispose, type MaybeRefOrGetter } from "vue";
import { useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import { useAuthStore } from "@/stores/auth";
import { resolveJoin, requestAccess, type JoinState } from "@/services/joinLinks";
import { toAppError } from "@/lib/errors";

/** Component-local state: raw token never becomes a persistent query-cache key. */
export function useProjectJoin(token: MaybeRefOrGetter<string>) {
  const auth = useAuthStore();
  const client = useQueryClient();
  const state = ref<JoinState>();
  const loading = ref(false), sending = ref(false), error = ref("");
  let generation = 0;
  onScopeDispose(() => { generation++; });
  async function applyState(result: JoinState, current: number) {
    if (current !== generation) return;
    if (result.state === "member") {
      await Promise.all([qk.project.root(result.project_id), qk.me.projects()].map(queryKey => client.invalidateQueries({ queryKey })));
    }
    if (current === generation) state.value = result;
  }
  async function refresh() {
    const current = ++generation;
    state.value = undefined; loading.value = true; error.value = "";
    try { const result = await resolveJoin(toValue(token)); await applyState(result, current); }
    catch (e) { if (current === generation) error.value = toAppError(e).message; }
    finally { if (current === generation) loading.value = false; }
  }
  async function request() {
    if (sending.value) return;
    const current = generation;
    sending.value = true; error.value = "";
    try { const result = await requestAccess(toValue(token)); await applyState(result, current); }
    catch (e) { if (current === generation) { error.value = toAppError(e).message; const result = await resolveJoin(toValue(token)).catch(() => undefined); if (result) await applyState(result, current); } }
    finally { sending.value = false; }
  }
  watch(() => [toValue(token), auth.userId, auth.ready], () => { if (auth.ready) void refresh(); }, { immediate: true });
  return { state, loading, sending, error, refresh, request };
}

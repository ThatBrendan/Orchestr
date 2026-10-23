import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useQuery, useQueryClient } from "@tanstack/vue-query";
import { listDecisions } from "@/services/decisions";
import { qk } from "./keys";
export function useDecisions(project: MaybeRefOrGetter<string>, decision?: MaybeRefOrGetter<string>) {
  const client = useQueryClient();
  const list = useQuery({
    queryKey: computed(() => [...qk.project.root(toValue(project)), "decisions", decision ? toValue(decision) : "all"]),
    queryFn: () => listDecisions(toValue(project), decision ? toValue(decision) : undefined),
    refetchInterval: 15_000,
  });
  function refresh(projectId = toValue(project)) {
    return Promise.all([qk.project.root(projectId), qk.me.notifications(), qk.me.attention(), qk.me.calendarRoot()]
      .map(queryKey => client.invalidateQueries({ queryKey })));
  }
  return { list, refresh };
}

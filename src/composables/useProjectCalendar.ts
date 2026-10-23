import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { useQuery } from '@tanstack/vue-query';
import { qk } from './keys';
import { listProjectCalendar } from '@/services/calendar';
export function useProjectCalendar(project: MaybeRefOrGetter<string>, start: MaybeRefOrGetter<string>, end: MaybeRefOrGetter<string>) {
  return useQuery({
    // Nested under timeline so existing source mutation invalidation also refreshes Calendar.
    queryKey: computed(() => [...qk.project.timeline(toValue(project)), 'calendar', toValue(start), toValue(end)]),
    queryFn: () => listProjectCalendar(toValue(project), toValue(start), toValue(end)),
    enabled: computed(() => !!toValue(project) && !!toValue(start) && !!toValue(end)),
    staleTime: 0,
    refetchInterval: 30_000,
  });
}

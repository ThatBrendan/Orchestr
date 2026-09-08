import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as calendarService from "@/services/calendar";

export function useGlobalCalendar(startIso: MaybeRefOrGetter<string>, endIso: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.me.calendar(toValue(startIso), toValue(endIso))),
    queryFn: () => calendarService.listMyTimelineEvents(toValue(startIso), toValue(endIso)),
    staleTime: 0,
  });
  return {
    events: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

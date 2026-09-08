import { computed } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as peopleService from "@/services/people";

export function useGlobalPeople() {
  const q = useQuery({
    queryKey: qk.me.people(),
    queryFn: () => peopleService.listMyPeople(),
  });
  return {
    people: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

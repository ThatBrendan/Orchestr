import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
export function useCostShares(id: MaybeRefOrGetter<string | undefined>) {
  return useQuery({
    queryKey: computed(() => ["activity-cost-shares", toValue(id)]),
    enabled: computed(() => !!toValue(id)),
    staleTime: 0,
    queryFn: async () => {
      const { data, error } = await supabase.from("v_activity_cost_shares").select("*").eq("commitment_id", toValue(id)!);
      if (error) throw toAppError(error);
      return data;
    },
  });
}

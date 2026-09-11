import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
export function useMemberSettlement(id: MaybeRefOrGetter<string>) {
  return useQuery({ queryKey: computed(() => ["settlement", "activity", toValue(id)]), queryFn: async () => {
    const { data, error } = await supabase.from("v_activity_member_settlements").select("*").eq("commitment_id",toValue(id));
    if (error) throw toAppError(error); return data;
  }});
}

export function useProjectSettlement(id: MaybeRefOrGetter<string>, enabled: MaybeRefOrGetter<boolean> = true) {
  return useQuery({ queryKey: computed(() => ["settlement", "project", toValue(id)]), enabled: computed(() => toValue(enabled)), queryFn: async () => {
    const [members, totals] = await Promise.all([
      supabase.from("v_project_member_settlements").select("*").eq("project_id",toValue(id)),
      supabase.from("v_project_settlement_totals").select("*").eq("project_id",toValue(id)).maybeSingle(),
    ]);
    if (members.error) throw toAppError(members.error);
    if (totals.error) throw toAppError(totals.error);
    return { members: members.data, totals: totals.data };
  }});
}

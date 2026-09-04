import { computed } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { qk } from "./keys";
import { useAuth } from "./useAuth";
import { useMyProjects } from "./useProjects";
import * as profileService from "@/services/profile";
import * as derived from "@/services/derived";

export function useMyProfile() {
  const { userId } = useAuth();
  const q = useQuery({
    queryKey: computed(() => qk.me.profile(userId.value ?? "anon")),
    queryFn: () => profileService.getMyProfile(userId.value!),
    enabled: computed(() => !!userId.value),
  });
  return { profile: q.data, isPending: q.isPending };
}

/**
 * Dashboard "Needs attention" — ONE set-based call to public.get_my_attention()
 * (was: get_project_health per project → client N+1). Count comes from
 * v_my_projects.attention_count, so no extra round-trip for the headline number.
 */
export function useDashboardAttention() {
  const { projects } = useMyProjects();

  const q = useQuery({
    queryKey: qk.me.attention(),
    queryFn: derived.getMyAttention,
    staleTime: 0,
  });

  const findings = computed(() => q.data.value ?? []);
  const totalCount = computed(() =>
    projects.value.reduce((sum, p) => sum + (p.attention_count ?? 0), 0),
  );

  return {
    findings,
    totalCount,
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

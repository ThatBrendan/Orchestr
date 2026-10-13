import { computed, ref, watch } from "vue";
import { useMutation, useQuery, useQueryClient } from "@tanstack/vue-query";
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

export function useUpdateMyDisplayName() {
  const { userId } = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: (displayName: string) => profileService.updateMyDisplayName(userId.value!, displayName),
    onSuccess: (profile) => {
      client.setQueryData(qk.me.profile(profile.id), profile);
      void client.invalidateQueries({ queryKey: qk.me.profile(profile.id) });
      void client.invalidateQueries({ queryKey: ["project"] });
      void client.invalidateQueries({ queryKey: qk.me.people() });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

/**
 * Dashboard attention: bounded five-row pages in the authoritative RPC order.
 * PostgREST returns the exact count with the same response; no client N+1.
 */
export function useDashboardAttention() {
  const { activeProjects: projects } = useMyProjects();
  const { userId } = useAuth();
  const page = ref(1);
  watch(() => `${userId.value}:${projects.value.map(p => p.project_id).sort().join(',')}`, () => { page.value = 1; });
  const q = useQuery({
    queryKey: computed(() => [...qk.me.attention(), userId.value, page.value]),
    queryFn: () => derived.getMyAttention(page.value),
    enabled: computed(() => !!userId.value),
    staleTime: 0,
  });
  watch(q.data, data => {
    if (data) page.value = Math.min(data.page, Math.max(1, Math.ceil(data.total / 5)));
  });
  const findings = computed(() => q.data.value?.items ?? []);
  const totalCount = computed(() => q.data.value?.total ?? projects.value.reduce((sum, p) => sum + (p.attention_count ?? 0), 0));
  return {
    findings, totalCount, page,
    canGoPrevious: computed(() => page.value > 1),
    canGoNext: computed(() => page.value * 5 < totalCount.value),
    isPending: q.isPending,
    isFetching: q.isFetching,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

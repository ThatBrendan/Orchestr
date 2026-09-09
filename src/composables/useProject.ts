import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as projectsService from "@/services/projects";
import * as derived from "@/services/derived";
import * as members from "@/services/members";

export function useProject(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.detail(toValue(projectId))),
    queryFn: () => projectsService.getProject(toValue(projectId)),
  });
  return { project: q.data, isPending: q.isPending, isError: q.isError, error: q.error };
}

export function useProjectFinancials(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.financials(toValue(projectId))),
    queryFn: () => derived.getProjectFinancials(toValue(projectId)),
    staleTime: 0,
  });
  return { financials: q.data, isPending: q.isPending, isError: q.isError, error: q.error, refetch: q.refetch };
}

export function useProjectOverview(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.overview(toValue(projectId))),
    queryFn: () => derived.getProjectOverview(toValue(projectId)),
    staleTime: 0,
  });
  return { overview: q.data, isPending: q.isPending, isError: q.isError, error: q.error, refetch: q.refetch };
}

export function useProjectHealth(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.health(toValue(projectId))),
    queryFn: () => derived.getProjectHealth(toValue(projectId)),
    staleTime: 0,
  });
  const findings = computed(() => q.data.value ?? []);
  const needsAttention = computed(() =>
    findings.value
      .filter((f) => !f.dismissed && (f.severity === "blocker" || f.severity === "warning"))
      .sort((a, b) => (a.severity === "blocker" ? -1 : b.severity === "blocker" ? 1 : 0)),
  );
  return { findings, needsAttention, isPending: q.isPending, isError: q.isError, error: q.error, refetch: q.refetch };
}

export function useProjectHealthSummary(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.healthSummary(toValue(projectId))),
    queryFn: () => derived.getProjectHealthSummary(toValue(projectId)),
    staleTime: 0,
  });
  return { summary: q.data, isPending: q.isPending, isError: q.isError, error: q.error, refetch: q.refetch };
}

export function useBudgetCategoryActuals(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.budgetCategories(toValue(projectId))),
    queryFn: () => derived.getBudgetCategoryActuals(toValue(projectId)),
    staleTime: 0,
  });
  return {
    categories: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useUpcoming(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.upcoming(toValue(projectId))),
    queryFn: () => derived.getUpcomingEvents(toValue(projectId)),
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

export function useFullTimeline(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.timeline(toValue(projectId))),
    queryFn: () => derived.getFullTimeline(toValue(projectId)),
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

export function useMemberDirectory(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.members(toValue(projectId))),
    queryFn: () => members.listMemberDirectory(toValue(projectId)),
  });
  return {
    members: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

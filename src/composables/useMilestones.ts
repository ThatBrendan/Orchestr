import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as milestonesService from "@/services/milestones";
import type { TablesInsert, TablesUpdate } from "@/types/database";

export function useMilestones(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.milestones(toValue(projectId))),
    queryFn: () => milestonesService.listMilestones(toValue(projectId)),
  });
  return {
    milestones: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useCreateMilestone(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: TablesInsert<"milestones">) => milestonesService.createMilestone(input),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.milestones(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.overview(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useUpdateMilestone(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { id: string; patch: TablesUpdate<"milestones"> }) =>
      milestonesService.updateMilestone(input.id, input.patch),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.milestones(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.overview(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useDeleteMilestone(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => milestonesService.deleteMilestone(id),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.milestones(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.overview(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

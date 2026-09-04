import { computed } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as projectsService from "@/services/projects";
import type { ProjectInsert } from "@/types/domain";

export function useMyProjects() {
  const q = useQuery({
    queryKey: qk.me.projects(),
    queryFn: projectsService.listMyProjects,
  });
  return {
    projects: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useCreateProject() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: ProjectInsert) => projectsService.createProject(input),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.me.projects() });
    },
  });
}

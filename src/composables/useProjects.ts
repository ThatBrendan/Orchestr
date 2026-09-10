import { computed } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as projectsService from "@/services/projects";
import type { ProjectInsert } from "@/types/domain";
import type { ProjectStatus, TablesUpdate } from "@/types/database";

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
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.people() });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useUpdateProject(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (patch: Omit<TablesUpdate<"projects">, "status" | "deleted_at">) =>
      projectsService.updateProject(projectId, patch),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.root(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.people() });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useSetProjectStatus(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (status: ProjectStatus) => projectsService.setProjectStatus(projectId, status),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.root(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.people() });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useDeleteProject(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => projectsService.softDeleteProject(projectId),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.root(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.people() });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

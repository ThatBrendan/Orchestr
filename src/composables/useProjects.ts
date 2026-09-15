import { projectGroup } from "@/lib/projectLifecycle";
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
    activeProjects: computed(() => (q.data.value ?? []).filter(p => projectGroup(p.status) === "active")),
    pastProjects: computed(() => (q.data.value ?? []).filter(p => projectGroup(p.status) === "past")),
    archivedProjects: computed(() => (q.data.value ?? []).filter(p => projectGroup(p.status) === "archived")),
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
    mutationFn: (change: { status: ProjectStatus; from?: ProjectStatus }) => projectsService.setProjectStatus(projectId, change.status, change.from),
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

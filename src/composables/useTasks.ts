import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as tasksService from "@/services/tasks";
import type { TablesInsert, TablesUpdate } from "@/types/database";
import type { TaskStatus } from "@/services/tasks";

export function useTasks(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.tasks(toValue(projectId))),
    queryFn: () => tasksService.listTasks(toValue(projectId)),
  });
  return {
    tasks: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useCreateTask(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: TablesInsert<"tasks">) => tasksService.createTask(input),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.tasks(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.health(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.overview(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
    },
  });
}

export function useUpdateTask(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { id: string; patch: Omit<TablesUpdate<"tasks">, "status" | "deleted_at"> }) =>
      tasksService.updateTask(input.id, input.patch),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.tasks(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.health(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.overview(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
    },
  });
}

export function useSetTaskStatus(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { id: string; status: TaskStatus }) => tasksService.setTaskStatus(input.id, input.status),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.tasks(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.health(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.overview(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
    },
  });
}

export function useDeleteTask(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => tasksService.softDeleteTask(id),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.tasks(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.health(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(projectId) });
      void client.invalidateQueries({ queryKey: qk.project.overview(projectId) });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
    },
  });
}

export function useTaskOccurrences(
  taskId: MaybeRefOrGetter<string>,
  startDate: MaybeRefOrGetter<string>,
  endDate: MaybeRefOrGetter<string>,
) {
  const q = useQuery({
    queryKey: computed(() => qk.task.occurrences(toValue(taskId), toValue(startDate), toValue(endDate))),
    queryFn: () => tasksService.listTaskOccurrences(toValue(taskId), toValue(startDate), toValue(endDate)),
    staleTime: 0,
  });
  return {
    occurrences: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useCompleteTaskOccurrence(projectId: MaybeRefOrGetter<string>, taskId: MaybeRefOrGetter<string>) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (occurrenceDate: string) => tasksService.completeTaskOccurrence(toValue(taskId), occurrenceDate),
    onSuccess: () => {
      const pid = toValue(projectId);
      const tid = toValue(taskId);
      void client.invalidateQueries({ queryKey: qk.project.tasks(pid) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(pid) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(pid) });
      void client.invalidateQueries({ queryKey: qk.project.health(pid) });
      void client.invalidateQueries({ queryKey: qk.project.overview(pid) });
      void client.invalidateQueries({ queryKey: qk.task.occurrencesRoot(tid) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useSkipTaskOccurrence(projectId: MaybeRefOrGetter<string>, taskId: MaybeRefOrGetter<string>) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (occurrenceDate: string) => tasksService.skipTaskOccurrence(toValue(taskId), occurrenceDate),
    onSuccess: () => {
      const pid = toValue(projectId);
      const tid = toValue(taskId);
      void client.invalidateQueries({ queryKey: qk.project.timeline(pid) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(pid) });
      void client.invalidateQueries({ queryKey: qk.project.health(pid) });
      void client.invalidateQueries({ queryKey: qk.project.overview(pid) });
      void client.invalidateQueries({ queryKey: qk.task.occurrencesRoot(tid) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

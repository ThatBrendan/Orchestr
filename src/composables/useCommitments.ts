import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import { invalidatePlanning } from "./invalidation";
import * as commitmentsService from "@/services/commitments";
import * as derived from "@/services/derived";
import type { TablesInsert, TablesUpdate, CommitmentStatus } from "@/types/database";

function invalidateCommitmentEffects(client: ReturnType<typeof useQueryClient>, projectId: string) {
  return invalidatePlanning(client, projectId, [
    qk.project.commitments(projectId), qk.project.tasks(projectId),
    qk.project.budgetCategories(projectId), qk.project.milestones(projectId),
  ]);
}

export function useCommitments(projectId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.project.commitments(toValue(projectId))),
    queryFn: () => commitmentsService.listCommitments(toValue(projectId)),
  });
  return {
    commitments: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useCreateCommitment(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: TablesInsert<"commitments">) => commitmentsService.createCommitment(input),
    onSuccess: () => {
      return invalidateCommitmentEffects(client, projectId);
    },
  });
}

export function useUpdateCommitment(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { id: string; patch: Omit<TablesUpdate<"commitments">, "status" | "deleted_at"> }) =>
      commitmentsService.updateCommitment(input.id, input.patch),
    onSuccess: (_data, input) => {
      void client.invalidateQueries({ queryKey: qk.commitment.financials(input.id) });
      void client.invalidateQueries({ queryKey: qk.commitment.occurrencesRoot(input.id) });
      return invalidateCommitmentEffects(client, projectId);
    },
  });
}

export function useSetCommitmentStatus(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { id: string; status: CommitmentStatus }) =>
      commitmentsService.setCommitmentStatus(input.id, input.status),
    onSuccess: (_data, input) => {
      void client.invalidateQueries({ queryKey: qk.commitment.payments(input.id) });
      void client.invalidateQueries({ queryKey: qk.commitment.financials(input.id) });
      void client.invalidateQueries({ queryKey: qk.commitment.occurrencesRoot(input.id) });
      return invalidateCommitmentEffects(client, projectId);
    },
  });
}

export function useCommitmentOccurrences(
  commitmentId: MaybeRefOrGetter<string>,
  startDate: MaybeRefOrGetter<string>,
  endDate: MaybeRefOrGetter<string>,
) {
  const q = useQuery({
    queryKey: computed(() => qk.commitment.occurrences(toValue(commitmentId), toValue(startDate), toValue(endDate))),
    queryFn: () =>
      commitmentsService.listCommitmentOccurrences(
        toValue(commitmentId),
        toValue(startDate),
        toValue(endDate),
      ),
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

export function useCompleteCommitmentOccurrence(
  projectId: MaybeRefOrGetter<string>,
  commitmentId: MaybeRefOrGetter<string>,
) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (occurrenceDate: string) =>
      commitmentsService.completeCommitmentOccurrence(toValue(commitmentId), occurrenceDate),
    onSuccess: () => {
      const pid = toValue(projectId);
      const cid = toValue(commitmentId);
      void client.invalidateQueries({ queryKey: qk.project.commitments(pid) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(pid) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(pid) });
      void client.invalidateQueries({ queryKey: qk.project.health(pid) });
      void client.invalidateQueries({ queryKey: qk.project.overview(pid) });
      void client.invalidateQueries({ queryKey: qk.commitment.occurrencesRoot(cid) });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.project.financials(pid) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useSkipCommitmentOccurrence(
  projectId: MaybeRefOrGetter<string>,
  commitmentId: MaybeRefOrGetter<string>,
) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { date: string; reason: string }) =>
      commitmentsService.skipCommitmentOccurrence(toValue(commitmentId), input.date, input.reason),
    onSuccess: () => {
      const pid = toValue(projectId);
      const cid = toValue(commitmentId);
      void client.invalidateQueries({ queryKey: qk.project.timeline(pid) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(pid) });
      void client.invalidateQueries({ queryKey: qk.project.health(pid) });
      void client.invalidateQueries({ queryKey: qk.project.overview(pid) });
      void client.invalidateQueries({ queryKey: qk.commitment.occurrencesRoot(cid) });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.project.financials(pid) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useStopCommitmentRecurrence(
  projectId: MaybeRefOrGetter<string>,
  commitmentId: MaybeRefOrGetter<string>,
) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (stopAfter: string) =>
      commitmentsService.stopCommitmentRecurrence(toValue(commitmentId), stopAfter),
    onSuccess: () => {
      const pid = toValue(projectId);
      const cid = toValue(commitmentId);
      void client.invalidateQueries({ queryKey: qk.project.commitments(pid) });
      void client.invalidateQueries({ queryKey: qk.project.timeline(pid) });
      void client.invalidateQueries({ queryKey: qk.project.upcoming(pid) });
      void client.invalidateQueries({ queryKey: qk.project.health(pid) });
      void client.invalidateQueries({ queryKey: qk.project.overview(pid) });
      void client.invalidateQueries({ queryKey: qk.commitment.occurrencesRoot(cid) });
      void client.invalidateQueries({ queryKey: qk.me.projects() });
      void client.invalidateQueries({ queryKey: qk.project.financials(pid) });
      void client.invalidateQueries({ queryKey: qk.me.attention() });
      void client.invalidateQueries({ queryKey: qk.me.calendarRoot() });
    },
  });
}

export function useDeleteCommitment(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => commitmentsService.softDeleteCommitment(id),
    onSuccess: () => {
      return invalidateCommitmentEffects(client, projectId);
    },
  });
}

export function useCommitmentFinancials(commitmentId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.commitment.financials(toValue(commitmentId))),
    queryFn: () => derived.getCommitmentFinancials(toValue(commitmentId)),
    staleTime: 0,
  });
  return { financials: q.data, isPending: q.isPending, isError: q.isError, error: q.error, refetch: q.refetch };
}

export function useParticipants(commitmentId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.commitment.participants(toValue(commitmentId))),
    queryFn: () => commitmentsService.listParticipants(toValue(commitmentId)),
  });
  return {
    participants: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useAddParticipant(projectId: string, commitmentId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: TablesInsert<"commitment_participants">) => commitmentsService.addParticipant(input),
    onSuccess: () => {
      return invalidatePlanning(client, projectId, [qk.commitment.participants(commitmentId)]);
    },
  });
}

export function useRemoveParticipant(projectId: string, commitmentId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (participantId: string) => commitmentsService.removeParticipant(participantId),
    onSuccess: () => {
      return invalidatePlanning(client, projectId, [qk.commitment.participants(commitmentId)]);
    },
  });
}

export function useSaveCommitmentOccurrenceNote(projectId: MaybeRefOrGetter<string>, commitmentId: MaybeRefOrGetter<string>) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { date: string; note: string | null }) =>
      commitmentsService.saveCommitmentOccurrenceNote(toValue(commitmentId), input.date, input.note),
    onSuccess: () => invalidatePlanning(client, toValue(projectId), [qk.commitment.occurrencesRoot(toValue(commitmentId))]),
  });
}

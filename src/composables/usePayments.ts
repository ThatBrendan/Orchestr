import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as paymentsService from "@/services/payments";
import type { TablesInsert, TablesUpdate } from "@/types/database";

export function usePayments(commitmentId: MaybeRefOrGetter<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.commitment.payments(toValue(commitmentId))),
    queryFn: () => paymentsService.listPayments(toValue(commitmentId)),
  });
  return {
    payments: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

/** projectId is only used to also invalidate project-level financials/health after a mutation. */
function invalidatePaymentEffects(
  client: ReturnType<typeof useQueryClient>,
  projectId: string,
  commitmentId: string,
) {
  void client.invalidateQueries({ queryKey: qk.commitment.payments(commitmentId) });
  void client.invalidateQueries({ queryKey: qk.commitment.financials(commitmentId) });
  void client.invalidateQueries({ queryKey: qk.project.financials(projectId) });
  void client.invalidateQueries({ queryKey: qk.project.health(projectId) });
  void client.invalidateQueries({ queryKey: qk.project.timeline(projectId) });
}

export function useCreatePayment(projectId: string, commitmentId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: TablesInsert<"payments">) => paymentsService.createPayment(input),
    onSuccess: () => invalidatePaymentEffects(client, projectId, commitmentId),
  });
}

export function useUpdatePayment(projectId: string, commitmentId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { id: string; patch: Omit<TablesUpdate<"payments">, "status" | "deleted_at"> }) =>
      paymentsService.updatePayment(input.id, input.patch),
    onSuccess: () => invalidatePaymentEffects(client, projectId, commitmentId),
  });
}

export function useMarkPaymentPaid(projectId: string, commitmentId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: {
      id: string;
      paid_on: string;
      paid_by_member_id?: string | null;
      method?: string | null;
      reference?: string | null;
    }) => {
      const { id, ...rest } = input;
      return paymentsService.markPaymentPaid(id, rest);
    },
    onSuccess: () => invalidatePaymentEffects(client, projectId, commitmentId),
  });
}

export function useSetPaymentStatus(projectId: string, commitmentId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { id: string; status: "scheduled" | "waived" | "cancelled" }) =>
      paymentsService.setPaymentStatus(input.id, input.status),
    onSuccess: () => invalidatePaymentEffects(client, projectId, commitmentId),
  });
}

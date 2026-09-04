import { useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as health from "@/services/health";
import type { FindingRef } from "@/services/health";

function invalidateHealth(client: ReturnType<typeof useQueryClient>, projectId: string) {
  void client.invalidateQueries({ queryKey: qk.project.health(projectId) });
  void client.invalidateQueries({ queryKey: qk.project.healthSummary(projectId) });
  void client.invalidateQueries({ queryKey: qk.me.attention() });
  void client.invalidateQueries({ queryKey: qk.me.projects() }); // attention_count per project
}

export function useDismissFinding(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (finding: FindingRef) => health.dismissFinding(projectId, finding),
    onSuccess: () => invalidateHealth(client, projectId),
  });
}

export function useSnoozeFinding(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { finding: FindingRef; days?: number }) =>
      health.snoozeFinding(projectId, input.finding, input.days),
    onSuccess: () => invalidateHealth(client, projectId),
  });
}

export function useReactivateFinding(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (finding: FindingRef) => health.reactivateFinding(projectId, finding),
    onSuccess: () => invalidateHealth(client, projectId),
  });
}

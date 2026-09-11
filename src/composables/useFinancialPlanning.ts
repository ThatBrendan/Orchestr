import { useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import { invalidatePlanning } from "./invalidation";
import * as financials from "@/services/financialPlanning";

export function useFinancialPlanning() {
  const client = useQueryClient();
  const refresh = (projectId: string, id?: string) => invalidatePlanning(client, projectId, [
    qk.project.commitments(projectId), qk.project.budgetCategories(projectId),
    qk.project.healthSummary(projectId), qk.project.health(projectId),
    qk.admin.project(projectId), qk.admin.projectHealth(projectId), qk.admin.overview(), ["admin", "projects"],
    ...(id ? [qk.commitment.financials(id)] : []),
  ]);
  const budget = useMutation({
    mutationFn: (input: { projectId: string; amount: number | null }) => financials.setProjectBudget(input.projectId, input.amount),
    onSuccess: (_, input) => refresh(input.projectId),
  });
  const actual = useMutation({
    mutationFn: (input: { projectId: string; id: string; amount: number | null; complete: boolean }) => financials.setActualCost(input.id, input.amount, input.complete),
    onSuccess: (_, input) => refresh(input.projectId, input.id),
  });
  return { budget, actual };
}

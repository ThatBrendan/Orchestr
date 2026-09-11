/** Presentation only: payments remain separate, never added to planned costs. */
export function budgetVisual(target: number | null, planned: number, paid: number) {
  const scale = Math.max(target ?? 0, planned, Math.abs(paid), 1);
  const within = target == null ? planned : Math.min(planned, target);
  const over = target == null ? 0 : Math.max(planned - target, 0);
  const width = (amount: number) => Math.max(0, Math.min(100, amount / scale * 100));
  return { within, over, plannedWidth: width(within), overWidth: width(over), paidWidth: width(Math.abs(paid)) };
}

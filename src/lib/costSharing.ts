/** UUID ordering matches PostgreSQL; each remainder penny goes to the earliest member. */
export function evenShares(cost: number, members: string[]): Record<string, number> {
  if (!Number.isSafeInteger(cost) || cost < 0 || members.length === 0 || new Set(members).size !== members.length) throw new Error("Choose members and a valid cost.");
  const total = BigInt(cost), count = BigInt(members.length);
  return Object.fromEntries([...members].sort().map((id, i) => [id, Number(total / count + (BigInt(i) < total % count ? 1n : 0n))]));
}

/** Exact decimal draft, without dividing currency through floating point. */
export function shareInput(minor: number, digits: number): string {
  const value = BigInt(minor).toString().padStart(digits + 1, "0");
  return digits === 0 ? value : `${value.slice(0, -digits)}.${value.slice(-digits)}`;
}

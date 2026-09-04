/**
 * Money formatting ONLY — no arithmetic on business figures (docs/TECHNICAL_ARCHITECTURE.md §5).
 * All amounts are integer minor units in the project's single currency.
 */
const MINOR_DIGITS: Record<string, number> = { JPY: 0, KRW: 0, KWD: 3, BHD: 3 };

export function useMoney() {
  function format(minor: number | null | undefined, currency: string): string {
    if (minor == null) return "—";
    const digits = MINOR_DIGITS[currency] ?? 2;
    const major = minor / 10 ** digits;
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency,
        minimumFractionDigits: digits,
        maximumFractionDigits: digits,
      }).format(major);
    } catch {
      return `${currency} ${major.toFixed(digits)}`;
    }
  }
  return { format };
}

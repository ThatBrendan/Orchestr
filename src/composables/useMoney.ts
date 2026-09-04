/**
 * Money formatting ONLY — no arithmetic on business figures (docs/TECHNICAL_ARCHITECTURE.md §5).
 * All amounts are integer minor units in the project's single currency.
 */
const MINOR_DIGITS: Record<string, number> = { JPY: 0, KRW: 0, KWD: 3, BHD: 3 };

export function useMoney() {
  function digitsFor(currency: string): number {
    return MINOR_DIGITS[currency] ?? 2;
  }
  function format(minor: number | null | undefined, currency: string): string {
    if (minor == null) return "—";
    const digits = digitsFor(currency);
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
  /** Parse a form input's major-unit string (e.g. "120.50") into integer minor units. */
  function toMinor(majorInput: string | number, currency: string): number | null {
    const major = typeof majorInput === "number" ? majorInput : Number.parseFloat(majorInput);
    if (!Number.isFinite(major)) return null;
    const digits = digitsFor(currency);
    return Math.round(major * 10 ** digits);
  }
  /** Minor units back to a plain major-unit number, for pre-filling a form input. */
  function toMajor(minor: number | null | undefined, currency: string): number | null {
    if (minor == null) return null;
    return minor / 10 ** digitsFor(currency);
  }
  return { format, toMinor, toMajor, digitsFor };
}

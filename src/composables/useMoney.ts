/**
 * Money formatting ONLY — no arithmetic on business figures (docs/TECHNICAL_ARCHITECTURE.md §5).
 * All amounts are integer minor units in the project's single currency.
 */
import { currencyDigits, parseMoney } from "@/lib/money";

export function useMoney() {
  const digitsFor = currencyDigits;
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
  const toMinor = parseMoney;
  /** Minor units back to a plain major-unit number, for pre-filling a form input. */
  function toMajor(minor: number | null | undefined, currency: string): number | null {
    if (minor == null) return null;
    return minor / 10 ** digitsFor(currency);
  }
  return { format, toMinor, toMajor, digitsFor };
}

export type MoneyInput = string | number | null | undefined;
const MINOR_DIGITS: Record<string, number> = { JPY: 0, KRW: 0, KWD: 3, BHD: 3 };
export const currencyDigits = (currency: string) => MINOR_DIGITS[currency] ?? 2;

/** Empty means unknown; malformed input throws. Decimal digits become integer minor units. */
export function parseMoney(input: MoneyInput, currency: string): number | null {
  if (input == null || input === "") return null;
  if (typeof input === "number" && !Number.isFinite(input)) throw new Error("Enter a finite amount.");
  const text = String(input).trim();
  if (!text) return null;
  if (!/^\d+(?:\.\d+)?$/.test(text)) throw new Error("Enter a non-negative amount using digits and a decimal point.");
  const [whole = "0", fraction = ""] = text.split(".");
  const digits = currencyDigits(currency);
  if (fraction.length > digits) throw new Error(`Use at most ${digits} decimal places for ${currency}.`);
  const minor = BigInt(whole) * (10n ** BigInt(digits)) + BigInt(fraction.padEnd(digits, "0") || "0");
  if (minor > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Amount is too large.");
  return Number(minor);
}

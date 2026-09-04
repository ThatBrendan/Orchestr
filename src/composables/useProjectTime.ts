import { DateTime } from "luxon";

/**
 * Render dates/times in the project's timezone (docs/TECHNICAL_ARCHITECTURE.md §5).
 * The project timezone is passed explicitly — never inferred from the browser.
 */
export function useProjectTime(timezone: string) {
  function dateTime(iso: string | null | undefined): string {
    if (!iso) return "—";
    return DateTime.fromISO(iso, { zone: timezone }).toFormat("ccc d LLL, HH:mm");
  }
  function dateOnly(iso: string | null | undefined): string {
    if (!iso) return "—";
    return DateTime.fromISO(iso, { zone: timezone }).toFormat("ccc d LLL");
  }
  function dayLabel(iso: string): string {
    return DateTime.fromISO(iso, { zone: timezone }).toFormat("cccc d LLL");
  }
  function time(iso: string): string {
    return DateTime.fromISO(iso, { zone: timezone }).toFormat("HH:mm");
  }
  /** "16–18 May 2027" style range for a project header. */
  function dateRange(startsOn: string | null, endsOn: string | null): string {
    const s = startsOn ? DateTime.fromISO(startsOn) : null;
    const e = endsOn ? DateTime.fromISO(endsOn) : null;
    if (s && e) {
      if (s.year === e.year && s.month === e.month) return `${s.day}–${e.day} ${e.toFormat("LLLL yyyy")}`;
      if (s.year === e.year) return `${s.toFormat("d LLL")} – ${e.toFormat("d LLL yyyy")}`;
      return `${s.toFormat("d LLL yyyy")} – ${e.toFormat("d LLL yyyy")}`;
    }
    if (s) return `From ${s.toFormat("d LLLL yyyy")}`;
    if (e) return e.toFormat("d LLLL yyyy");
    return "Dates not set";
  }
  return { dateTime, dateOnly, dayLabel, time, dateRange };
}

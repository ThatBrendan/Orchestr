import { config } from "@/config";

/** Redacting logger (docs/TECHNICAL_ARCHITECTURE.md §19). Never log tokens/emails/rows. */
type Level = "debug" | "info" | "warn" | "error";

function emit(level: Level, msg: string, ctx?: Record<string, unknown>) {
  if (level === "debug" && !config.isDev) return;
  // eslint-disable-next-line no-console
  (console[level] ?? console.log)(`[orchestrio] ${msg}`, ctx ?? "");
  // TODO(sentry): forward warn/error when config.sentryDsn is set.
}

export const logger = {
  debug: (m: string, c?: Record<string, unknown>) => emit("debug", m, c),
  info: (m: string, c?: Record<string, unknown>) => emit("info", m, c),
  warn: (m: string, c?: Record<string, unknown>) => emit("warn", m, c),
  error: (m: string, c?: Record<string, unknown>) => emit("error", m, c),
};

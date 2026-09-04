import { QueryClient } from "@tanstack/vue-query";
import { toAppError } from "./errors";
import { logger } from "./logger";

/** vue-query defaults (docs/TECHNICAL_ARCHITECTURE.md §4, §16). */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: (failureCount, error) => {
        const e = toAppError(error);
        if (e.kind === "network") return failureCount < 3;
        return false;
      },
      refetchOnWindowFocus: true,
    },
    mutations: {
      retry: false,
      onError: (error) => {
        const e = toAppError(error);
        if (e.kind === "unexpected" || e.kind === "server") {
          logger.error("mutation failed", { kind: e.kind, code: e.code });
        }
      },
    },
  },
});

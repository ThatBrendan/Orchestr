import type { PostgrestError } from "@supabase/supabase-js";

/**
 * Error taxonomy (docs/TECHNICAL_ARCHITECTURE.md §16).
 * Services throw these; composables/vue-query surface them.
 */
export type AppErrorKind =
  | "auth"
  | "permission"
  | "validation"
  | "not_found"
  | "conflict"
  | "rate_limit"
  | "network"
  | "server"
  | "unexpected";

export class AppError extends Error {
  readonly kind: AppErrorKind;
  readonly code?: string;
  readonly fieldErrors?: Record<string, string>;

  constructor(
    kind: AppErrorKind,
    message: string,
    opts: { code?: string; fieldErrors?: Record<string, string>; cause?: unknown } = {},
  ) {
    super(message, opts.cause !== undefined ? { cause: opts.cause } : undefined);
    this.name = "AppError";
    this.kind = kind;
    this.code = opts.code;
    this.fieldErrors = opts.fieldErrors;
  }
}

/** Trigger / RPC exceptions use `orchestr:<code>:<human text>` (docs/DATABASE_SCHEMA.md §7). */
function parseOrchestrMessage(msg: string): { code: string; text: string } | null {
  const m = /^orchestr:([a-z_]+):(.*)$/s.exec(msg);
  return m ? { code: m[1]!, text: m[2]!.trim() } : null;
}

const CONSTRAINT_MESSAGES: Record<string, string> = {
  uq_member_email_active: "That email is already a member of this project.",
  uq_invitation_pending: "There is already a pending invitation for that email.",
  chk_project_dates: "The end date must be on or after the start date.",
};

export function fromPostgrestError(err: PostgrestError): AppError {
  const orchestr = parseOrchestrMessage(err.message);
  if (orchestr) {
    const permissionCodes = new Set([
      "not_a_member",
      "not_organizer",
      "auth_required",
      "project_archived",
      "last_organizer",
      "forbidden_member_change",
      "platform_admin_required",
      "platform_role_locked",
    ]);
    if (permissionCodes.has(orchestr.code)) {
      return new AppError("permission", orchestr.text, { code: orchestr.code, cause: err });
    }
    return new AppError("validation", orchestr.text, { code: orchestr.code, cause: err });
  }

  switch (err.code) {
    case "23505": {
      const c = Object.keys(CONSTRAINT_MESSAGES).find((k) => err.message.includes(k));
      return new AppError("validation", c ? CONSTRAINT_MESSAGES[c]! : "That value is already taken.", {
        code: err.code,
        cause: err,
      });
    }
    case "23514":
    case "23502":
    case "23503": {
      const c = Object.keys(CONSTRAINT_MESSAGES).find((k) => err.message.includes(k));
      return new AppError("validation", c ? CONSTRAINT_MESSAGES[c]! : "That change isn't allowed.", {
        code: err.code,
        cause: err,
      });
    }
    case "42501":
    case "P0001":
      return new AppError("permission", "You don't have permission to do that.", { code: err.code, cause: err });
    case "PGRST116":
      return new AppError("not_found", "Not found.", { code: err.code, cause: err });
    default:
      return new AppError("server", err.message || "Something went wrong.", { code: err.code, cause: err });
  }
}

export function toAppError(e: unknown): AppError {
  if (e instanceof AppError) return e;
  if (e && typeof e === "object" && "message" in e && "code" in e) {
    return fromPostgrestError(e as PostgrestError);
  }
  if (e instanceof Error) {
    if (/fetch|network|Failed to fetch/i.test(e.message)) {
      return new AppError("network", "Network problem — check your connection.", { cause: e });
    }
    return new AppError("unexpected", e.message, { cause: e });
  }
  return new AppError("unexpected", "Something went wrong.", { cause: e });
}

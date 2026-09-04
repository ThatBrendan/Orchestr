import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { TablesInsert } from "@/types/database";

/**
 * Dismiss/snooze/reactivate a health finding (docs/BUSINESS_RULES.md HLT-F,
 * docs/SECURITY_RLS.md §5.12). Findings themselves are never written here — they are
 * always recomputed from live data (HLT-G); this only records the dismissal state
 * for a `(project, code, subject)` tuple. `blocker` findings are rejected by the DB
 * (`app.finding_is_dismissible` / `tg_dismissal_not_blocker`) regardless of what the
 * UI sends — the `dismissible` flag on the finding is an advisory mirror of that.
 */
export interface FindingRef {
  code: string;
  subject_type: string;
  subject_id: string | null;
}

export async function dismissFinding(projectId: string, finding: FindingRef): Promise<void> {
  const row: TablesInsert<"finding_dismissals"> = {
    project_id: projectId,
    code: finding.code,
    subject_type: finding.subject_type,
    subject_id: finding.subject_id,
    state: "dismissed",
    snoozed_until: null,
  };
  const { error } = await supabase
    .from("finding_dismissals")
    .upsert(row, { onConflict: "project_id,code,subject_type,subject_id" });
  if (error) throw toAppError(error);
}

export async function snoozeFinding(projectId: string, finding: FindingRef, days = 7): Promise<void> {
  const until = new Date();
  until.setDate(until.getDate() + days);
  const row: TablesInsert<"finding_dismissals"> = {
    project_id: projectId,
    code: finding.code,
    subject_type: finding.subject_type,
    subject_id: finding.subject_id,
    state: "snoozed",
    snoozed_until: until.toISOString().slice(0, 10),
  };
  const { error } = await supabase
    .from("finding_dismissals")
    .upsert(row, { onConflict: "project_id,code,subject_type,subject_id" });
  if (error) throw toAppError(error);
}

/** Undo a dismiss/snooze — deletes the dismissal row so the finding reappears (VAL-43). */
export async function reactivateFinding(projectId: string, finding: FindingRef): Promise<void> {
  let query = supabase
    .from("finding_dismissals")
    .delete()
    .eq("project_id", projectId)
    .eq("code", finding.code)
    .eq("subject_type", finding.subject_type);
  query = finding.subject_id === null ? query.is("subject_id", null) : query.eq("subject_id", finding.subject_id);
  const { error } = await query;
  if (error) throw toAppError(error);
}

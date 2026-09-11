import { supabase } from "@/lib/supabase";
import { AppError, toAppError } from "@/lib/errors";
import type { Tables, TablesInsert, TablesUpdate, CommitmentStatus, Json } from "@/types/database";
import type { CommitmentOccurrence } from "@/types/derived";

export type Commitment = Tables<"commitments">;
export type CommitmentParticipant = Tables<"commitment_participants">;

/** All non-deleted commitments for a project (docs/SECURITY_RLS.md §5.5). */
export async function listCommitments(projectId: string): Promise<Commitment[]> {
  const { data, error } = await supabase
    .from("commitments")
    .select("*")
    .eq("project_id", projectId)
    .order("starts_at", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function createCommitment(input: TablesInsert<"commitments"> & { costSplit?: Json }): Promise<Commitment> {
  const { costSplit, project_id, ...fields } = input;
  const { data, error } = await supabase.rpc("save_activity_with_split", { p_project: project_id, p_commitment: null, p_fields: fields, p_split: costSplit ?? null });
  if (error) throw toAppError(error);
  return data;
}

/** Field edit (title, type, category, owner, schedule, location, supplier/booking, notes) — status changes separately. */
export async function updateCommitment(
  id: string,
  patch: Omit<TablesUpdate<"commitments">, "status" | "deleted_at">,
  costSplit?: Json,
): Promise<Commitment> {
  const { data: current, error: readError } = await supabase.from("commitments").select("project_id").eq("id", id).single();
  if (readError) throw toAppError(readError);
  const { data, error } = await supabase.rpc("save_activity_with_split", { p_project: current.project_id, p_commitment: id, p_fields: patch, p_split: costSplit ?? null });
  if (error) throw toAppError(error);
  return data;
}

/** Status transition — legality enforced by `app.tg_commitment_status_transition`. */
export async function setCommitmentStatus(id: string, status: CommitmentStatus): Promise<Commitment> {
  const { data, error } = await supabase.from("commitments").update({ status }).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

export async function listCommitmentOccurrences(
  commitmentId: string,
  startDate: string,
  endDate: string,
): Promise<CommitmentOccurrence[]> {
  const { data, error } = await supabase.rpc("get_commitment_occurrences", {
    p_commitment: commitmentId,
    p_start: startDate,
    p_end: endDate,
  });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function completeCommitmentOccurrence(commitmentId: string, occurrenceDate: string): Promise<void> {
  const { error } = await supabase.rpc("complete_commitment_occurrence", {
    p_commitment: commitmentId,
    p_occurrence_date: occurrenceDate,
  });
  if (error) throw toAppError(error);
}

export async function skipCommitmentOccurrence(commitmentId: string, occurrenceDate: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("skip_commitment_occurrence", {
    p_commitment: commitmentId,
    p_occurrence_date: occurrenceDate,
    p_reason: reason,
  });
  if (error) throw toAppError(error);
}

export async function stopCommitmentRecurrence(commitmentId: string, stopAfter: string): Promise<void> {
  const { error } = await supabase.rpc("stop_commitment_recurrence", {
    p_commitment: commitmentId,
    p_stop_after: stopAfter,
  });
  if (error) throw toAppError(error);
}

/** Soft delete — organizer, creator, or owner only (docs/SECURITY_RLS.md §5.5). */
export async function softDeleteCommitment(id: string): Promise<void> {
  const { data, error } = await supabase.rpc("soft_delete_commitment", { p_commitment: id });
  if (error) throw toAppError(error);
  if (data !== id) throw new AppError("not_found", "Not found or cannot be deleted.");
}

export async function listParticipants(commitmentId: string): Promise<CommitmentParticipant[]> {
  const { data, error } = await supabase
    .from("commitment_participants")
    .select("*")
    .eq("commitment_id", commitmentId);
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function addParticipant(
  input: TablesInsert<"commitment_participants">,
): Promise<CommitmentParticipant> {
  const { data, error } = await supabase.from("commitment_participants").insert(input).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Hard delete — correct for participants (docs/SECURITY_RLS.md §5.6). */
export async function removeParticipant(participantId: string): Promise<void> {
  const { error, count } = await supabase.from("commitment_participants").delete({ count: "exact" }).eq("id", participantId);
  if (error) throw toAppError(error);
  if (count !== 1) throw new AppError("not_found", "Not found or cannot be removed.");
}

export async function saveCommitmentOccurrenceNote(commitmentId: string, occurrenceDate: string, note: string | null) {
  const { error } = await supabase.rpc("save_commitment_occurrence_note", {
    p_commitment: commitmentId, p_occurrence_date: occurrenceDate, p_note: note,
  });
  if (error) throw toAppError(error);
}

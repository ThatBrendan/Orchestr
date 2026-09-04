import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { Tables, TablesInsert, TablesUpdate, CommitmentStatus } from "@/types/database";

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

export async function createCommitment(input: TablesInsert<"commitments">): Promise<Commitment> {
  const { data, error } = await supabase.from("commitments").insert(input).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Field edit (title, kind, owner, schedule, location, booking, notes) — status changes separately. */
export async function updateCommitment(
  id: string,
  patch: Omit<TablesUpdate<"commitments">, "status" | "deleted_at">,
): Promise<Commitment> {
  const { data, error } = await supabase.from("commitments").update(patch).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Status transition — legality enforced by `app.tg_commitment_status_transition`. */
export async function setCommitmentStatus(id: string, status: CommitmentStatus): Promise<Commitment> {
  const { data, error } = await supabase.from("commitments").update({ status }).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Soft delete — organizer, creator, or owner only (docs/SECURITY_RLS.md §5.5). */
export async function softDeleteCommitment(id: string): Promise<void> {
  const { error } = await supabase.from("commitments").update({ deleted_at: new Date().toISOString() }).eq(
    "id",
    id,
  );
  if (error) throw toAppError(error);
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
  const { error } = await supabase.from("commitment_participants").delete().eq("id", participantId);
  if (error) throw toAppError(error);
}

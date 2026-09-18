import { trackProductEvent } from "@/lib/analytics";
import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { Tables, TablesInsert, TablesUpdate } from "@/types/database";

export type Payment = Tables<"payments">;

/** All non-deleted payments for a commitment (docs/SECURITY_RLS.md §5.8). */
export async function listPayments(commitmentId: string): Promise<Payment[]> {
  const { data, error } = await supabase
    .from("payments")
    .select("*")
    .is("deleted_at", null)
    .eq("commitment_id", commitmentId)
    .order("due_on", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function createPayment(input: TablesInsert<"payments">): Promise<Payment> {
  const { data, error } = await supabase.from("payments").insert(input).select("*").single();
  if (error) throw toAppError(error);
  trackProductEvent("payment_recorded");
  return data;
}

/** Field edit — status changes go through `markPaymentPaid` / `setPaymentStatus`. */
export async function updatePayment(
  id: string,
  patch: Omit<TablesUpdate<"payments">, "status" | "deleted_at">,
): Promise<Payment> {
  const { data, error } = await supabase.from("payments").update(patch).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

export async function setPaymentStatus(
  id: string,
  status: "scheduled" | "waived" | "cancelled",
): Promise<Payment> {
  const { data, error } = await supabase.from("payments").update({ status }).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Mark paid — `paid_on` must be today or earlier in the project's timezone (VAL-16). */
export async function markPaymentPaid(
  id: string,
  input: { paid_on: string; paid_by_member_id?: string | null; method?: string | null; reference?: string | null },
): Promise<Payment> {
  const { data, error } = await supabase
    .from("payments")
    .update({ status: "paid", ...input })
    .eq("id", id)
    .select("*")
    .single();
  if (error) throw toAppError(error);
  return data;
}

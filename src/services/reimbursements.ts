import { supabase } from '@/lib/supabase';
import { toAppError } from '@/lib/errors';
export async function listReimbursements(projectId: string, activityId?: string) {
  let q = supabase.from('v_reimbursements').select('*').eq('project_id', projectId);
  if (activityId) q = q.eq('commitment_id', activityId);
  const { data, error } = await q.order('created_at').order('id');
  if (error) throw toAppError(error);
  return data ?? [];
}
export async function reimbursementSuggestions(paymentId: string) {
  const { data, error } = await supabase.rpc('get_reimbursement_suggestions', { p_payment: paymentId });
  if (error) throw toAppError(error);
  return data ?? [];
}
export async function createReimbursement(input: { paymentId: string; memberId: string; amount: number }) {
  const { data, error } = await supabase.rpc('create_reimbursement', { p_payment: input.paymentId, p_debtor: input.memberId, p_amount: input.amount });
  if (error) throw toAppError(error);
  return data;
}
export async function cancelReimbursement(id: string) {
  const { error } = await supabase.rpc('cancel_reimbursement', { p_request: id });
  if (error) throw toAppError(error);
}

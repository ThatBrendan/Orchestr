import { supabase } from '@/lib/supabase';
import { toAppError } from '@/lib/errors';
export async function getPaymentStatus(request: string) {
  const { data, error } = await supabase.from('v_reimbursement_payment_status').select('*').eq('reimbursement_request_id', request).single();
  if (error) throw toAppError(error);
  return data;
}
export async function acknowledgePayment(request: string) {
  const { data, error } = await supabase.rpc('acknowledge_reimbursement_payment', { p_request: request });
  if (error) throw toAppError(error);
  return data;
}
export async function withdrawPayment(acknowledgement: string) {
  const { error } = await supabase.rpc('withdraw_reimbursement_payment_acknowledgement', { p_acknowledgement: acknowledgement });
  if (error) throw toAppError(error);
}

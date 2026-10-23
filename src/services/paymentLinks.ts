import { supabase } from '@/lib/supabase';
import { toAppError } from '@/lib/errors';
import type { PaymentProvider } from '@/types/paymentLinks';
export async function listMyPaymentLinks() {
  const { data, error } = await supabase.rpc('list_my_payment_links');
  if (error) throw toAppError(error); return data ?? [];
}
export async function saveMyPaymentLink(input: { id?: string; provider: PaymentProvider; url: string; label: string; enabled: boolean }) {
  const { data, error } = await supabase.rpc('save_my_payment_link', { p_id: input.id, p_provider: input.provider, p_url: input.url, p_label: input.label, p_enabled: input.enabled });
  if (error) throw toAppError(error); return data;
}
export async function deleteMyPaymentLink(id: string) {
  const { error } = await supabase.rpc('delete_my_payment_link', { p_id: id });
  if (error) throw toAppError(error);
}
export async function setDefaultPaymentLink(id: string | null) {
  const { error } = await supabase.rpc('set_default_payment_link', { p_id: id });
  if (error) throw toAppError(error);
}
export async function getReimbursementPaymentOptions(id: string) {
  const { data, error } = await supabase.rpc('get_reimbursement_payment_options', { p_request: id });
  if (error) throw toAppError(error); return data ?? [];
}

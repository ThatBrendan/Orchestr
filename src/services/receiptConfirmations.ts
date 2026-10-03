import { supabase } from '@/lib/supabase';
import { toAppError } from '@/lib/errors';
export async function confirmReceipt(acknowledgement: string) {
 const { data, error } = await supabase.rpc('confirm_reimbursement_receipt', { p_acknowledgement: acknowledgement });
 if (error) throw toAppError(error);
 return data;
}

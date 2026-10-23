export type Reimbursement = {
  id: string; project_id: string; commitment_id: string; payment_id: string;
  debtor_member_id: string; creditor_member_id: string; amount_minor: number;
  source_amount_minor: number; source_paid_on: string;
  status: 'open' | 'cancelled' | 'settled'; created_at: string; cancelled_at: string | null;
  activity_title: string; currency: string; debtor_name: string; creditor_name: string;
  needs_review: boolean; can_cancel: boolean; is_debtor: boolean; is_creditor: boolean;
};
export type ReimbursementSuggestion = {
  payment_id: string; commitment_id: string; debtor_member_id: string; debtor_name: string;
  creditor_member_id: string; creditor_name: string; amount_minor: number;
};
export type ReimbursementNotification = {
  id: string; created_at: string; read_at: string | null; reimbursement_id: string;
  project_id: string; commitment_id: string; amount_minor: number; currency: string;
  creditor_name: string; activity_title: string; needs_review: boolean;
};

export type ReimbursementRequest = {
 id: string; project_id: string; commitment_id: string; payment_id: string;
 debtor_member_id: string; creditor_member_id: string; amount_minor: number;
 status: 'open' | 'cancelled' | 'settled'; basis_hash: string; created_by: string;
 cancelled_by: string | null; created_at: string; updated_at: string; cancelled_at: string | null;
};

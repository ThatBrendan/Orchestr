export type PaymentAcknowledgement = {
  id: string; project_id: string; reimbursement_request_id: string; debtor_member_id: string;
  created_by_user_id: string; acknowledged_at: string; withdrawn_at: string | null;
};
export type PaymentAcknowledgementHistory = Pick<PaymentAcknowledgement, 'id' | 'acknowledged_at' | 'withdrawn_at'>;
export type ReimbursementPaymentStatus = {
  reimbursement_request_id: string; active_acknowledgement_id: string | null;
  can_acknowledge: boolean; can_withdraw: boolean; history: PaymentAcknowledgementHistory[];
};
export type PaymentAcknowledgementNotification = {
  id: string; kind: 'reimbursement_payment_acknowledged' | 'reimbursement_payment_acknowledgement_withdrawn';
  created_at: string; read_at: string | null; reimbursement_id: string; project_id: string;
  commitment_id: string; amount_minor: number; currency: string; debtor_name: string;
  activity_title: string; needs_review: boolean;
};

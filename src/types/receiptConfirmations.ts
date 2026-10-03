export type ReceiptConfirmation = {
 id: string; project_id: string; reimbursement_request_id: string; acknowledgement_id: string;
 creditor_member_id: string; settlement_group_id: string; confirmed_at: string; created_by_user_id: string;
};
export type ReceiptConfirmationNotification = {
 id: string; created_at: string; read_at: string | null; reimbursement_id: string; project_id: string;
 commitment_id: string; amount_minor: number; currency: string; creditor_name: string; activity_title: string;
 confirmation_state: 'settled' | 'reversed';
};

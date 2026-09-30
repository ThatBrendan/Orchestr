export type PaymentProvider = 'monzo' | 'revolut' | 'custom';
export type PaymentLink = {
  id: string; user_id: string; provider: PaymentProvider; payment_url: string;
  display_label: string; is_enabled: boolean; is_default: boolean;
  created_at: string; updated_at: string; deleted_at: string | null;
};
export type PaymentOption = Pick<PaymentLink, 'id' | 'provider' | 'payment_url' | 'display_label' | 'is_default'>;

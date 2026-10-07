export type CalendarConnection = {
  id: string;
  user_id: string;
  provider: 'google';
  status: 'disconnected' | 'connected' | 'reauthorization_required' | 'degraded' | 'provisioning';
  account_label: string | null;
  activities: boolean;
  decisions: boolean;
  payments: boolean;
  last_synced_at: string | null;
  last_error_code: string | null;
  created_at: string;
  updated_at: string;
};

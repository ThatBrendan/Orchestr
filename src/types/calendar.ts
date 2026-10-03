import type { ActivityType } from './database';
export interface CalendarEntry {
  entry_id: string;
  source_type: 'activity' | 'activity_occurrence' | 'decision' | 'payment_schedule';
  source_id: string;
  project_id: string;
  title: string;
  start_at: string | null;
  end_at: string | null;
  start_date: string | null;
  end_date: string | null;
  all_day: boolean;
  status: string;
  activity_id: string | null;
  activity_title: string | null;
  activity_type: ActivityType | null;
  category_name: string | null;
  assigned_member: string | null;
  amount_minor: number | null;
  currency_code: string | null;
  occurrence_date: string | null;
}

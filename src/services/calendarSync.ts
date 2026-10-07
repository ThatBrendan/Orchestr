import { supabase } from '@/lib/supabase';

export async function getCalendarConnection() {
  const { data, error } = await supabase.from('user_calendar_connections').select('*').maybeSingle();
  if (error) throw new Error('Calendar sync settings are unavailable.');
  return data;
}
export async function requestCalendarSync(preferences: { activities?: boolean; decisions?: boolean; payments?: boolean } = {}) {
  const { error } = await supabase.rpc('request_calendar_sync', { p_activities: preferences.activities, p_decisions: preferences.decisions, p_payments: preferences.payments });
  if (error) throw new Error('Could not request calendar sync. Please try again.');
}
export async function calendarAction(action: 'config' | 'disconnect') {
  const { data, error } = await supabase.functions.invoke(`calendar-integration/${action}`, { body: {} });
  if (error) throw new Error('Calendar integration is unavailable. Your Orchestrio data is unaffected.');
  return data as { configured?: boolean; disconnected?: boolean; cleanup_required?: boolean };
}
export async function connectCalendar() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('Please sign in again.');
  // Top-level POST establishes the HttpOnly provider-domain binding cookie.
  // The short-lived Orchestrio JWT is in the body, never the URL/history.
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/calendar-integration/start`;
  const input = document.createElement('input');
  input.type = 'hidden'; input.name = 'access_token'; input.value = session.access_token;
  form.append(input); document.body.append(form); form.submit(); form.remove();
}

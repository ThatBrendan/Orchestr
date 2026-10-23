import { createClient } from 'npm:@supabase/supabase-js@2';
import { GoogleCalendarProvider } from './provider.mjs';
import { createHandler } from './handler.mjs';

declare const EdgeRuntime: { waitUntil(work: Promise<unknown>): void };

const appUrl = Deno.env.get('APP_URL') ?? 'http://localhost:5173';
const clientId = Deno.env.get('GOOGLE_CALENDAR_CLIENT_ID') ?? '';
const clientSecret = Deno.env.get('GOOGLE_CALENDAR_CLIENT_SECRET') ?? '';
const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const redirectUri = `${supabaseUrl}/functions/v1/calendar-integration/callback`;
const client = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: (input: RequestInfo | URL, init?: RequestInit) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) }) },
});
const backend = async (action: string, data: Record<string, unknown> = {}) => {
  const result = action === 'authorize_worker'
    ? await client.rpc('calendar_worker_wakeup')
    : await client.rpc('calendar_backend', { p_action: action, p_data: data });
  if (result.error) throw { code: result.error.code }; // Safe code only, never server details.
  return result.data;
};
const allowedOrigins = ['http://localhost:5173', 'http://127.0.0.1:5173', new URL(appUrl).origin];
Deno.serve(createHandler({
  backend,
  provider: new GoogleCalendarProvider({ clientId, clientSecret, redirectUri }),
  appUrl,
  configured: Boolean(clientId && clientSecret && Deno.env.get('APP_URL')),
  allowedOrigins,
  authenticate: async (jwt: string) => { const { data, error } = await client.auth.getUser(jwt); return error ? null : data.user; },
  background: (work: Promise<unknown>) => EdgeRuntime.waitUntil(work),
}));

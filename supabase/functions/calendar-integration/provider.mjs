/** Google adapter. No provider response body, URL, or token escapes an error. */
export class ProviderError extends Error {
  constructor(code, status = 0) { super(code); this.code = code; this.status = status; }
}
export const GOOGLE_SCOPE = 'openid email https://www.googleapis.com/auth/calendar.app.created';
export class GoogleCalendarProvider {
  constructor({ clientId, clientSecret, redirectUri, fetchImpl = fetch }) {
    Object.assign(this, { clientId, clientSecret, redirectUri, fetchImpl });
  }
  authorizationUrl(state, challenge) {
    const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    url.search = new URLSearchParams({ client_id: this.clientId, redirect_uri: this.redirectUri, response_type: 'code', scope: GOOGLE_SCOPE, access_type: 'offline', prompt: 'consent', state, code_challenge: challenge, code_challenge_method: 'S256' }).toString();
    return url.href;
  }
  async request(url, options = {}) {
    let response;
    try { response = await this.fetchImpl(url, { ...options, signal: AbortSignal.timeout(8000), redirect: 'error' }); }
    catch { throw new ProviderError('transient'); }
    let data = {};
    try { if (response.status !== 204) data = await response.json(); } catch { /* No raw response in logs/errors. */ }
    if (!response.ok) {
      const reasons = data?.error?.errors?.map(e => e.reason) ?? [];
      const code = data?.error === 'invalid_grant' || response.status === 401 ? 'auth'
        : response.status === 429 || reasons.some(r => ['rateLimitExceeded', 'userRateLimitExceeded', 'quotaExceeded'].includes(r)) ? 'quota'
        : response.status >= 500 ? 'transient' : 'permanent';
      throw new ProviderError(code, response.status);
    }
    return data;
  }
  async token(parameters) {
    const result = await this.request('https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: this.clientId, client_secret: this.clientSecret, ...parameters }),
    });
    if (!result.access_token || !Number.isFinite(result.expires_in)) throw new ProviderError('auth');
    return { access_token: result.access_token, refresh_token: result.refresh_token, expires_at: new Date(Date.now() + result.expires_in * 1000).toISOString() };
  }
  exchange(code, verifier) { return this.token({ code, code_verifier: verifier, redirect_uri: this.redirectUri, grant_type: 'authorization_code' }); }
  refreshAuth(refresh_token) { return this.token({ refresh_token, grant_type: 'refresh_token' }); }
  async identity(token) {
    const result = await this.request('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: `Bearer ${token}` } });
    if (!result.sub || !result.email || !result.email_verified) throw new ProviderError('auth');
    return { subject: result.sub, email: result.email };
  }
  api(token, path, method = 'GET', body) {
    return this.request('https://www.googleapis.com/calendar/v3/' + path, {
      method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  }
  createCalendar(token) { return this.api(token, 'calendars', 'POST', { summary: 'Orchestrio', description: 'Managed by Orchestrio. Changes are overwritten by authoritative sync.', timeZone: 'UTC' }); }
  async checkCalendar(token, calendar) {
    try { await this.api(token, `calendars/${encodeURIComponent(calendar)}`); }
    catch (e) { if (e.status === 404 || e.status === 410) throw new ProviderError('calendar_missing'); throw e; }
  }
  async upsertEvent(token, calendar, id, event) {
    const path = `calendars/${encodeURIComponent(calendar)}/events`;
    try {
      const result = await this.api(token, `${path}/${id}`, 'PUT', event);
      if (result.status === 'cancelled') throw new ProviderError('event_deleted', 410);
      return result;
    }
    catch (e) {
      if (e.status === 410) throw new ProviderError('event_deleted', 410);
      if (e.status !== 404) throw e;
    }
    try { return await this.api(token, path, 'POST', { ...event, id }); }
    catch (e) {
      // An ambiguous prior POST may already have succeeded with this reserved ID.
      if (e.status === 409) {
        const existing = await this.api(token, `${path}/${id}`);
        if (existing.status === 'cancelled') throw new ProviderError('event_deleted', 410);
        return this.api(token, `${path}/${id}`, 'PUT', event);
      }
      if (e.status === 410) throw new ProviderError('event_deleted', 410);
      throw e;
    }
  }
  async deleteEvent(token, calendar, id) {
    try { await this.api(token, `calendars/${encodeURIComponent(calendar)}/events/${id}`, 'DELETE'); }
    catch (e) { if (![404, 410].includes(e.status)) throw e; }
  }
  async deleteCalendar(token, calendar) {
    try { await this.api(token, `calendars/${encodeURIComponent(calendar)}`, 'DELETE'); }
    catch (e) { if (![404, 410].includes(e.status)) throw e; }
  }
  revoke(token) { return this.request('https://oauth2.googleapis.com/revoke', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ token }) }); }
}

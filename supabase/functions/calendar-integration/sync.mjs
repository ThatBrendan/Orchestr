import { mapEvent } from './mapping.mjs';
import { ProviderError } from './provider.mjs';

/** Each invocation is bounded. DB leases and durable reserved IDs survive crashes. */
export async function syncOne({ backend, provider, appUrl, maxOperations = 20, budgetMilliseconds = 45000 }) {
  const deadline = Date.now() + budgetMilliseconds;
  const job = await backend('claim');
  if (!job) return false;
  const run = (action, data = {}) => backend(action, { job_id: job.id, lease: job.lease, ...data });
  let provisioning = false;
  try {
    const bundle = await run('bundle');
    let token = bundle.access_token;
    if (Date.parse(bundle.expires_at) < Date.now() + 60000) {
      const refreshed = await provider.refreshAuth(bundle.refresh_token);
      await run('token', refreshed); token = refreshed.access_token;
    }
    // Revalidate lease/connection immediately before every outbound operation.
    const guard = () => run('bundle');
    let calendar = bundle.calendar_id;
    if (!calendar) {
      await run('provision_begin'); provisioning = true;
      const created = await provider.createCalendar(token);
      if (!created.id) throw new ProviderError('provisioning_uncertain');
      await run('provision_finish', { calendar_id: created.id });
      provisioning = false; calendar = created.id;
    }
    await guard(); await provider.checkCalendar(token, calendar);
    const entries = await run('projection');
    const wanted = new Map(entries.map(entry => [entry.entry_id, mapEvent(entry, appUrl)]).filter(([, event]) => event !== null));
    const links = await run('links');
    // Cursor order spans desired upserts and obsolete deletions. A fresh full pass
    // follows completion, so source changes behind the cursor converge next pass.
    const actions = [...wanted.keys()].map(key => ({ key: 'u:' + key, source: key, type: 'upsert' }))
      .concat(links.filter(link => !wanted.has(link.source_key)).map(link => ({ key: 'd:' + link.source_key, source: link.source_key, type: 'delete', link })))
      .sort((a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0).filter(action => action.key > job.cursor_key);
    let count = 0;
    for (const action of actions) {
      if (count++ >= maxOperations || Date.now() >= deadline) { await run('yield'); return true; }
      if (action.type === 'delete') {
        await guard(); await provider.deleteEvent(token, calendar, action.link.provider_event_id);
        await run('deleted', { source_key: action.source });
      } else {
        let link = await run('reserve', { source_key: action.source });
        const event = wanted.get(action.source);
        await guard();
        try { await provider.upsertEvent(token, calendar, link.provider_event_id, event); }
        catch (e) {
          if (e.code !== 'event_deleted') throw e;
          await run('rotate', { source_key: action.source });
          link = await run('reserve', { source_key: action.source });
          await guard(); await provider.upsertEvent(token, calendar, link.provider_event_id, event);
        }
        await run('synced', { source_key: action.source });
      }
      await run('checkpoint', { cursor_key: action.key });
    }
    await run('finish');
  } catch (error) {
    const code = provisioning ? 'provisioning_uncertain' : error.code === '54000' ? 'capacity' : error instanceof ProviderError ? error.code : 'transient';
    try { await run('fail', { code }); } catch { /* Disconnect/lease loss wins; never resurrect a job. */ }
  }
  return true;
}

export async function disconnect({ backend, provider, userId }) {
  // Local disable and secret erasure commits BEFORE any network request.
  const bundle = await backend('disconnect', { user_id: userId });
  let cleanup = true, revocationToken = bundle.refresh_token;
  if (bundle.calendar_id && bundle.access_token) {
    try { await provider.deleteCalendar(bundle.access_token, bundle.calendar_id); }
    catch (error) {
      if (error.code === 'auth' && bundle.refresh_token) {
        try {
          const refreshed = await provider.refreshAuth(bundle.refresh_token);
          revocationToken = refreshed.refresh_token ?? revocationToken;
          await provider.deleteCalendar(refreshed.access_token, bundle.calendar_id);
        } catch { cleanup = false; }
      } else cleanup = false;
    }
  }
  if (revocationToken) {
    try { await provider.revoke(revocationToken); } catch { cleanup = false; }
  }
  if (!cleanup && bundle.id) await backend('cleanup_warning', { id: bundle.id });
  return { disconnected: true, cleanup_required: !cleanup };
}

<script setup lang="ts">
import { computed, ref } from 'vue';
import { useQuery } from '@tanstack/vue-query';
import { useAuthStore } from '@/stores/auth';
import { useRoute, useRouter } from 'vue-router';
import AppButton from '@/components/ui/AppButton.vue';
import { calendarAction, connectCalendar, getCalendarConnection, requestCalendarSync } from '@/services/calendarSync';
const auth = useAuthStore(), route = useRoute(), router = useRouter();
const busy = ref(false), error = ref(''), message = ref(''), confirming = ref(false);
if (route.query.calendar_result) {
  message.value = route.query.calendar_result === 'connected' ? 'Google Calendar connected. Initial sync is queued.' : 'Google Calendar could not connect. Try again when the integration is available.';
  const query = { ...route.query }; delete query.calendar_result;
  void router.replace({ query });
}
const connection = useQuery({ queryKey: computed(() => ['calendar-connection', auth.userId]), enabled: computed(() => auth.isAuthenticated), queryFn: getCalendarConnection, refetchInterval: 30000 });
const config = useQuery({ queryKey: computed(() => ['calendar-config', auth.userId]), enabled: computed(() => auth.isAuthenticated), queryFn: () => calendarAction('config'), retry: false });
const row = computed(() => connection.data.value);
const connected = computed(() => row.value?.status === 'connected');
const active = computed(() => row.value && row.value.status !== 'disconnected');
const uncertain = computed(() => row.value?.status === 'provisioning' || row.value?.last_error_code === 'provisioning_uncertain');
const status = computed(() => !active.value ? 'Not connected' : connected.value ? 'Connected' : uncertain.value ? 'Calendar setup needs attention' : 'Reconnect required');
const preferences = [{ key: 'activities', label: 'Activities', description: 'Includes recurring occurrences.' }, { key: 'decisions', label: 'Decisions', description: 'Deadline markers.' }, { key: 'payments', label: 'Payments', description: 'Due dates and titles only. Amounts are excluded.' }] as const;
async function act(action: () => Promise<unknown>, success = '') {
  busy.value = true; error.value = ''; message.value = '';
  try { await action(); if (success) message.value = success; await connection.refetch(); }
  catch (e) { error.value = e instanceof Error ? e.message : 'Calendar sync is unavailable.'; }
  finally { busy.value = false; }
}
async function remove() {
  await act(async () => {
    const result = await calendarAction('disconnect');
    confirming.value = false;
    if (result.cleanup_required) message.value = 'Disconnected locally. Remove the Orchestrio calendar and revoke access in your Google account manually.';
  });
}
</script>
<template>
  <section
    id="calendar-sync-settings"
    class="mt-8 space-y-4 border-t border-line pt-6"
    aria-labelledby="calendar-sync-title"
    data-testid="calendar-sync-settings"
  >
    <h2
      id="calendar-sync-title"
      class="text-section-heading font-semibold"
    >
      Calendar sync
    </h2>
    <p class="text-meta text-muted">
      When connected, send project dates to a dedicated Google calendar. Orchestrio remains the source of truth.
    </p>
    <details class="text-meta text-muted">
      <summary class="min-h-11 py-3 cursor-pointer rounded-lg focus-ring">
        What calendar sync includes
      </summary>
      <p>Sync runs about every 15 minutes across a rolling 30 days past and 90 days ahead. External edits are overwritten. Only dates you can currently read are exported. Titles are included, so keep sensitive information out of titles. Decision deadlines use a 30-minute marker. Timed Activities without an end stay internal-only; add an end to export them.</p>
    </details>
    <p
      v-if="connection.isPending.value"
      role="status"
    >
      Loading calendar settings…
    </p>
    <p
      v-else-if="connection.isError.value"
      role="alert"
    >
      Calendar settings are unavailable. <button
        class="inline-flex min-h-11 items-center rounded-lg underline focus-ring"
        @click="connection.refetch()"
      >
        Retry
      </button>
    </p>
    <template v-else>
      <div class="min-w-0">
        <p class="font-medium">
          Google Calendar · <span role="status">{{ status }}</span>
        </p>
        <p
          v-if="row?.account_label"
          class="break-all text-meta text-muted"
        >
          {{ row.account_label }}
        </p>
        <p
          v-if="row?.last_synced_at && active"
          class="text-meta text-muted"
        >
          Last synced {{ new Date(row.last_synced_at).toLocaleString() }}
        </p>
      </div>
      <p
        v-if="active && !connected"
        role="alert"
        class="text-meta"
      >
        {{ uncertain ? 'Setup could not be confirmed. Check Google for an Orchestrio calendar, then disconnect and remove it before connecting again.' : 'Calendar sync needs attention. Reconnect to resume; your Orchestrio workflows are unaffected.' }}
      </p>
      <p
        v-else-if="row?.last_error_code === 'cleanup_required'"
        role="alert"
        class="text-meta"
      >
        Disconnected locally. Remove the Orchestrio calendar and revoke access in your Google account manually.
      </p>
      <p
        v-else-if="row?.last_error_code"
        role="status"
        class="text-meta"
      >
        The last sync did not finish. Temporary errors retry automatically, up to five attempts. You can request another sync.
      </p>
      <template v-if="connected">
        <label
          v-for="preference in preferences"
          :key="preference.key"
          class="min-h-11 flex items-center justify-between gap-4"
        >
          <span><span class="block font-medium">{{ preference.label }}</span><span class="block text-meta text-muted">{{ preference.description }}</span></span>
          <input
            type="checkbox"
            class="h-5 w-5 shrink-0 focus-ring"
            :checked="row?.[preference.key]"
            :disabled="busy"
            :aria-label="`Sync ${preference.label.toLowerCase()}`"
            @change="act(() => requestCalendarSync({ [preference.key]: !row?.[preference.key] }), 'Preferences saved. Sync requested.')"
          >
        </label>
      </template>
      <p
        v-if="!config.isPending.value && !config.data.value?.configured"
        class="text-meta text-muted"
      >
        Google Calendar connection is not configured for this environment yet.
      </p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          v-if="!connected && !uncertain"
          variant="secondary"
          :disabled="busy || !config.data.value?.configured"
          @click="act(connectCalendar)"
        >
          {{ active ? 'Reconnect Google Calendar' : 'Connect Google Calendar' }}
        </AppButton>
        <AppButton
          v-if="connected"
          variant="secondary"
          :disabled="busy"
          @click="act(() => requestCalendarSync(), 'Sync requested.')"
        >
          Sync now
        </AppButton>
        <AppButton
          v-if="active"
          variant="secondary"
          :disabled="busy"
          @click="confirming = true"
        >
          Disconnect
        </AppButton>
      </div>
      <div
        v-if="confirming"
        class="space-y-3 rounded-lg border border-line p-3"
        role="group"
        aria-label="Confirm calendar disconnect"
      >
        <p class="text-meta">
          Disconnect and remove the dedicated Orchestrio calendar from Google? This removes its external events. Your Orchestrio dates stay unchanged. If Google is unavailable, you may need to remove the calendar and revoke access manually.
        </p>
        <div class="flex flex-wrap gap-2">
          <AppButton
            :disabled="busy"
            @click="remove"
          >
            Disconnect and remove calendar
          </AppButton>
          <AppButton
            variant="secondary"
            :disabled="busy"
            @click="confirming = false"
          >
            Cancel
          </AppButton>
        </div>
      </div>
    </template>
    <p
      v-if="message"
      role="status"
      class="text-meta"
    >
      {{ message }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-meta text-danger"
    >
      {{ error }}
    </p>
  </section>
</template>

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
    class="mt-8 space-y-4 rounded-xl border border-line bg-surface p-5"
    aria-labelledby="calendar-sync-title"
    data-testid="calendar-sync-settings"
  >
    <h2
      id="calendar-sync-title"
      class="font-display text-lg font-semibold"
    >
      Calendar sync
    </h2>
    <p class="text-13 text-muted">
      Send your Orchestrio dates to a dedicated Google calendar. Orchestrio stays authoritative; external edits are overwritten. Sync runs about every 15 minutes across a rolling 30 days past and 90 days ahead.
    </p>
    <p class="text-13 text-muted">
      Only dates you can currently read are exported. Titles are included, so keep sensitive information out of titles. Decision deadlines use a 30-minute marker. Timed Activities without an end stay internal-only; add an end to export them.
    </p>
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
        class="underline focus-ring"
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
          class="break-all text-13 text-muted"
        >
          {{ row.account_label }}
        </p>
        <p
          v-if="row?.last_synced_at && active"
          class="text-13 text-muted"
        >
          Last synced {{ new Date(row.last_synced_at).toLocaleString() }}
        </p>
      </div>
      <p
        v-if="active && !connected"
        role="alert"
        class="text-13"
      >
        {{ uncertain ? 'Setup could not be confirmed. Check Google for an Orchestrio calendar, then disconnect and remove it before connecting again.' : 'Calendar sync needs attention. Reconnect to resume; your Orchestrio workflows are unaffected.' }}
      </p>
      <p
        v-else-if="row?.last_error_code === 'cleanup_required'"
        role="alert"
        class="text-13"
      >
        Disconnected locally. Remove the Orchestrio calendar and revoke access in your Google account manually.
      </p>
      <p
        v-else-if="row?.last_error_code"
        role="status"
        class="text-13"
      >
        The last sync did not finish. Temporary errors retry automatically, up to five attempts. You can request another sync.
      </p>
      <template v-if="connected">
        <label
          v-for="preference in preferences"
          :key="preference.key"
          class="flex items-center justify-between gap-4"
        >
          <span><span class="block font-medium">{{ preference.label }}</span><span class="block text-13 text-muted">{{ preference.description }}</span></span>
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
        class="text-13 text-muted"
      >
        Google Calendar connection is not configured for this environment yet.
      </p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          v-if="!connected && !uncertain"
          :disabled="busy || !config.data.value?.configured"
          @click="act(connectCalendar)"
        >
          {{ active ? 'Reconnect Google Calendar' : 'Connect Google Calendar' }}
        </AppButton>
        <AppButton
          v-if="connected"
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
        <p class="text-13">
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
      class="text-13"
    >
      {{ message }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-13 text-danger"
    >
      {{ error }}
    </p>
  </section>
</template>

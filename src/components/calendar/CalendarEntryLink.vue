<script setup lang="ts">
import { DateTime } from 'luxon';
import type { CalendarEntry } from '@/types/calendar';
import { calendarRoute, calendarSource, calendarStatus, entryDay } from '@/lib/executionCalendar';
import { useMoney } from '@/composables/useMoney';
defineProps<{ entry: CalendarEntry; timezone: string; compact?: boolean; day?: string }>();
const money = useMoney();
</script>

<template>
  <RouterLink
    :to="calendarRoute(entry)"
    class="focus-ring block rounded border border-line px-2 py-1.5 text-xs hover:bg-surface-soft break-words"
    :class="['completed', 'resolved', 'paid', 'skipped'].includes(entry.status) ? 'text-muted' : 'text-ink'"
    :aria-label="`${calendarSource(entry)}: ${entry.title}, ${calendarStatus(entry)}`"
  >
    <span
      class="block font-medium"
      :class="compact ? 'truncate' : ''"
    >
      {{ entry.all_day ? 'All day' : day && entryDay(entry, timezone) < day ? 'Continues' : DateTime.fromISO(entry.start_at!, { zone: timezone }).toFormat('HH:mm') }} · {{ entry.title }}
    </span>
    <span
      class="block"
      :class="compact ? 'truncate' : ''"
    >{{ calendarSource(entry) }} · {{ calendarStatus(entry) }}</span>
    <template v-if="!compact">
      <span
        v-if="entry.end_at || entry.end_date"
        class="block"
      >Until {{ entry.end_date ?? DateTime.fromISO(entry.end_at!, { zone: timezone }).toFormat('d LLL yyyy, HH:mm') }}</span>
      <span
        v-if="entry.category_name"
        class="block"
      >{{ entry.category_name }}</span>
      <span
        v-if="entry.assigned_member"
        class="block"
      >Assigned to {{ entry.assigned_member }}</span>
      <span
        v-if="entry.source_type === 'payment_schedule'"
        class="block"
      >{{ money.format(entry.amount_minor, entry.currency_code!) }} · {{ entry.activity_title }}</span>
    </template>
  </RouterLink>
</template>

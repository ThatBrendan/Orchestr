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
    class="focus-ring block min-h-11 hover:bg-surface-subtle [overflow-wrap:anywhere]"
    :class="[compact ? 'rounded-lg px-1.5 py-2 border-l-2 text-meta' : 'rounded-lg p-4 text-sm', compact ? entry.source_type === 'decision' ? 'border-success' : entry.source_type === 'payment_schedule' ? 'border-warning' : 'border-brand' : '', ['completed', 'resolved', 'paid', 'skipped'].includes(entry.status) ? 'text-muted' : 'text-ink']"
    :aria-label="`${calendarSource(entry)}: ${entry.title}, ${calendarStatus(entry)}`"
    :title="compact ? `${calendarSource(entry)}: ${entry.title}` : undefined"
  >
    <span
      v-if="compact"
      class="block text-muted"
    >
      {{ entry.all_day ? 'All day' : day && entryDay(entry, timezone) < day ? 'Continues' : DateTime.fromISO(entry.start_at!, { zone: timezone }).toFormat('HH:mm') }} · {{ entry.source_type === 'decision' ? 'Decision' : entry.source_type === 'payment_schedule' ? 'Payment' : 'Activity' }}</span>
    <span
      class="font-semibold"
      :class="compact ? 'line-clamp-2' : 'block text-card-heading'"
    >{{ entry.title }}</span>
    <span
      v-if="!compact"
      class="mt-2 block text-meta text-ink-soft"
    >{{ entry.all_day ? 'All day' : day && entryDay(entry, timezone) < day ? 'Continues' : DateTime.fromISO(entry.start_at!, { zone: timezone }).toFormat('HH:mm') }} · <span :class="entry.source_type === 'decision' ? 'text-success' : entry.source_type === 'payment_schedule' ? 'text-warning' : 'text-brand'">{{ calendarSource(entry) }}</span> · {{ calendarStatus(entry) }}</span>
    <span
      v-else
      class="sr-only"
    >{{ calendarSource(entry) }} · {{ calendarStatus(entry) }}</span>
    <template v-if="!compact">
      <span
        v-if="entry.end_at || entry.end_date"
        class="mt-1 block text-meta text-muted"
      >Until {{ entry.end_date ?? DateTime.fromISO(entry.end_at!, { zone: timezone }).toFormat('d LLL yyyy, HH:mm') }}</span>
      <span
        v-if="entry.category_name"
        class="mt-1 block text-meta text-muted"
      >{{ entry.category_name }}</span>
      <span
        v-if="entry.assigned_member"
        class="mt-1 block text-meta text-muted"
      >Assigned to {{ entry.assigned_member }}</span>
      <span
        v-if="entry.source_type === 'payment_schedule'"
        class="mt-1 block text-meta text-muted"
      >{{ money.format(entry.amount_minor, entry.currency_code!) }} · {{ entry.activity_title }}</span>
    </template>
  </RouterLink>
</template>

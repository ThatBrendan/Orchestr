<script setup lang="ts">
import { computed } from 'vue';
import { DateTime } from 'luxon';
import type { CalendarEntry } from '@/types/calendar';
import { calendarRoute, calendarSource, calendarStatus, entryDay } from '@/lib/executionCalendar';
import AppIcon from '@/components/ui/AppIcon.vue';
const props = defineProps<{ entry: CalendarEntry; timezone: string; compact?: boolean; day?: string }>();
const time = computed(() => props.entry.all_day ? 'All day' : props.day && entryDay(props.entry, props.timezone) < props.day ? 'Continues' : DateTime.fromISO(props.entry.start_at!, { zone: props.timezone }).toFormat('HH:mm'));
const source = computed(() => props.entry.source_type === 'decision' ? 'Decision' : props.entry.source_type === 'payment_schedule' ? 'Payment' : 'Activity');
const tone = computed(() => props.entry.source_type === 'decision' ? 'bg-accent-soft text-accent' : props.entry.source_type === 'payment_schedule' ? 'bg-warning-soft text-warning' : 'bg-brand-soft text-brand');
const icon = computed(() => props.entry.source_type === 'decision' ? 'flag' : props.entry.source_type === 'payment_schedule' ? 'coins' : 'checkCircle');
</script>

<template>
  <RouterLink
    :to="calendarRoute(entry)"
    class="focus-ring block min-w-0 min-h-11 rounded-lg transition-colors"
    :class="compact ? ['px-2 py-1.5 text-xs', tone] : 'p-4 text-sm hover:bg-surface-subtle'"
    :aria-label="`${calendarSource(entry)}: ${entry.title}, ${calendarStatus(entry)}`"
    :aria-description="`${DateTime.fromISO(day ?? entryDay(entry, timezone), { zone: timezone }).toFormat('cccc, d LLLL yyyy')}, ${time}, ${timezone}${entry.source_type === 'activity_occurrence' ? ', recurring occurrence' : ''}`"
    :title="compact ? `${calendarSource(entry)}: ${entry.title} · ${time}` : undefined"
  >
    <template v-if="compact">
      <span class="flex items-center gap-1 min-w-0">
        <AppIcon
          :name="icon"
          :size="13"
          class="shrink-0"
        />
        <span class="truncate font-semibold">{{ entry.title }}</span>
      </span>
      <span class="block mt-0.5 truncate">{{ time }} · {{ source }}</span>
    </template>
    <div
      v-else
      class="flex items-start gap-3"
    >
      <span
        class="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg"
        :class="tone"
      ><AppIcon
        :name="icon"
        :size="18"
      /></span>
      <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
        <p class="text-meta text-ink-soft">
          {{ time }} · <span :class="entry.source_type === 'decision' ? 'text-accent' : entry.source_type === 'payment_schedule' ? 'text-warning' : 'text-brand'">{{ calendarSource(entry) }}</span>
        </p>
        <p class="mt-1 font-semibold text-ink">
          {{ entry.title }}
        </p>
        <p class="mt-1 text-meta text-muted">
          {{ calendarStatus(entry) }}<span v-if="entry.source_type === 'activity_occurrence'"> · Recurring occurrence</span>
        </p>
        <p
          v-if="entry.source_type === 'payment_schedule' && entry.activity_title"
          class="mt-1 text-meta text-muted"
        >
          For {{ entry.activity_title }}
        </p>
        <span class="mt-2 inline-flex items-center gap-1 text-meta font-medium text-brand">{{ entry.source_type === 'decision' ? 'Open decision' : entry.source_type === 'payment_schedule' ? 'Open payments' : 'Open Activity' }} <AppIcon
          name="arrowRight"
          :size="14"
        /></span>
      </div>
    </div>
  </RouterLink>
</template>

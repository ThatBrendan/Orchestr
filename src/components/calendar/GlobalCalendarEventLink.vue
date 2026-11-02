<script setup lang="ts">
import { computed } from 'vue';
import { DateTime } from 'luxon';
import type { GlobalTimelineEvent } from '@/types/derived';
import { globalEventRoute, globalEventSource, globalEventStatus, globalEventTypeLabel } from '@/lib/globalCalendarPresentation';
import AppIcon from '@/components/ui/AppIcon.vue';
import { useMoney } from '@/composables/useMoney';
const { format } = useMoney();
const props = defineProps<{event: GlobalTimelineEvent; compact?: boolean}>();
const source = computed(() => globalEventSource(props.event.subject_type));
const time = computed(() => props.event.all_day ? 'All day' : DateTime.fromISO(props.event.occurs_at, {zone: props.event.project_timezone}).toFormat('HH:mm'));
const label = computed(() => `${globalEventTypeLabel(props.event.event_type)}: ${props.event.title}, ${props.event.project_name}`);
const date = computed(() => DateTime.fromISO(props.event.occurs_at, {zone: props.event.project_timezone}).toFormat('cccc, d LLLL yyyy'));
const destination = computed(() => ({commitment: 'Open Activity', task: 'Open Activity', payment_schedule: 'Open payments', payment: 'Open Budget', milestone: 'Open Timeline'}[props.event.subject_type] ?? 'Open project'));
</script>
<template>
  <RouterLink
    :to="globalEventRoute(event)"
    class="focus-ring block min-w-0 min-h-11 rounded-lg transition-colors"
    :class="compact ? ['px-2 py-1.5 text-xs', source.tone] : 'p-4 text-sm hover:bg-surface-subtle'"
    :aria-label="label"
    :aria-description="`${date}, ${time}, ${event.project_timezone}${event.is_recurring_occurrence ? ', recurring occurrence' : ''}${globalEventStatus(event) ? ', ' + globalEventStatus(event) : ''}${event.amount_minor != null ? ', ' + format(event.amount_minor, event.currency) : ''}`"
    :title="compact ? `${label} · ${time} · ${event.project_timezone}` : undefined"
  >
    <template v-if="compact">
      <span class="flex items-center gap-1 min-w-0"><AppIcon
        :name="source.icon"
        :size="13"
        class="shrink-0"
      /><span class="truncate font-semibold">{{ event.title }}</span></span>
      <span class="block mt-0.5 truncate">{{ time }} · {{ source.label }}</span>
      <span class="block mt-0.5 truncate font-normal">{{ event.project_name }}</span>
    </template>
    <div
      v-else
      class="flex items-start gap-3"
    >
      <span
        class="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg"
        :class="source.tone"
      ><AppIcon
        :name="source.icon"
        :size="18"
      /></span>
      <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
        <p class="text-meta text-ink-soft">
          {{ time }} · <span :class="source.text">{{ globalEventTypeLabel(event.event_type) }}</span>
        </p>
        <p class="mt-1 font-semibold text-ink">
          {{ event.title }}
        </p>
        <p class="mt-1 text-meta text-muted">
          {{ event.project_name }}
        </p>
        <p class="mt-1 text-meta text-muted">
          {{ event.project_timezone }}
        </p>
        <p
          v-if="globalEventStatus(event) || event.is_recurring_occurrence"
          class="mt-1 text-meta text-muted"
        >
          {{ globalEventStatus(event) }}<span v-if="event.is_recurring_occurrence"> · Recurring occurrence</span>
        </p>
        <p
          v-if="event.amount_minor != null"
          class="mt-1 text-meta text-muted"
        >
          {{ format(event.amount_minor, event.currency) }}
        </p>
        <span class="mt-2 inline-flex items-center gap-1 text-meta font-medium text-brand">{{ destination }} <AppIcon
          name="arrowRight"
          :size="14"
        /></span>
      </div>
    </div>
  </RouterLink>
</template>

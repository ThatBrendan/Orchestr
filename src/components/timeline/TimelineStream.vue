<script setup lang="ts">
import { paymentScheduleLabels } from "@/lib/paymentSchedules";
import { computed } from "vue";
import type { TimelineEvent } from "@/types/derived";
import { useProjectTime } from "@/composables/useProjectTime";
import { DateTime } from "luxon";
import { userFacingActivityStatus } from "@/lib/presentation";

const props = defineProps<{ events: TimelineEvent[]; timezone: string }>();
const t = computed(() => useProjectTime(props.timezone));

// "Completed items" (BUSINESS_RULES §Timeline): a resolved commitment/payment is shown
// muted rather than looking identical to something still pending. "Upcoming deadlines"
// that have slipped into the past while still open (a due payment/task) are flagged —
// this is a purely visual read of already-derived fields, not a second health engine.
const DONE_STATUSES = new Set(["resolved", "completed", "cancelled", "paid", "skipped"]);
const DEADLINE_TYPES = new Set(["payment_due", "task_due", "recurring_commitment_due", "recurring_task_due"]);

interface Item {
  label: string;
  source: string;
  stamp: string;
  past: boolean;
  status: string | null;
  link: { name: string; params: { projectId: string; decisionId?: string }; query: Record<string,string> } | null;
  time: string;
  allDay: boolean;
  schedule: boolean;
  done: boolean;
  doneLabel: string;
  overdue: boolean;
}
interface Group {
  day: string;
  items: Item[];
}

const groups = computed<Group[]>(() => {
  const now = Date.now();
  const byDay = new Map<string, Group>();
  for (const e of props.events.filter(e=>e.subject_type!=='milestone')) {
    const day = DateTime.fromISO(e.occurs_at, { zone: props.timezone }).toFormat('cccc d LLL yyyy');
    if (!byDay.has(day)) byDay.set(day, { day, items: [] });
    const done = !!e.status && DONE_STATUSES.has(e.status);
    const isPast = new Date(e.occurs_at).getTime() < now;
    const time = e.all_day ? "" : t.value.time(e.occurs_at);
    byDay.get(day)!.items.push({
      label: e.title,
      source: e.subject_type === 'decision' ? 'Decision' : e.subject_type === 'payment_schedule' || e.subject_type === 'payment' ? 'Payment' : ['commitment', 'task'].includes(e.subject_type) ? 'Activity' : 'Project',
      stamp: e.occurs_at,
      past: isPast,
      schedule: e.subject_type === "payment_schedule",
      status: e.subject_type === "payment_schedule" ? (paymentScheduleLabels[e.status ?? ""] ?? null) : e.subject_type === "decision" ? ({ voting_open: "Voting open", voting_closed: "Voting closed", resolved: "Resolved" }[e.status ?? ""] ?? null) : e.is_recurring_occurrence ? e.status : null,
      link: e.subject_type === 'payment_schedule' ? {name:'project.commitments',params:{projectId:e.project_id},query:{commitment:e.subject_id,section:'payments'}} : e.subject_type === 'decision' ? { name: 'project.decision', params: { projectId: e.project_id, decisionId: e.subject_id }, query: {} } : ['commitment','task'].includes(e.subject_type) ? {name:'project.commitments',params:{projectId:e.project_id},query:{[e.subject_type==='task'?'item':'commitment']:e.subject_id,...(e.occurrence_date?{occurrence:e.occurrence_date}:{})}}:null,
      time: time === "00:00" ? "" : time,
      allDay: e.all_day,
      done,
      doneLabel: ({completed: "Complete", cancelled: "Cancelled", resolved: "Resolved", paid: "Paid", skipped: "Skipped"} as Record<string,string>)[e.status ?? ""] ?? "",
      overdue: e.subject_type === "payment_schedule" ? e.status === "overdue" : e.is_recurring_occurrence ? e.status === "overdue" : !done && isPast && DEADLINE_TYPES.has(e.event_type),
    });
  }
  return [...byDay.values()];
});
</script>

<template>
  <div class="space-y-6">
    <section
      v-for="g in groups"
      :key="g.day"
      :aria-label="g.day"
    >
      <h3 class="text-sm font-semibold text-ink-soft mb-3">
        {{ g.day }}
      </h3>
      <ol class="border-l border-line ml-2 pl-4 space-y-1">
        <li
          v-for="(i, idx) in g.items"
          :key="idx"
          class="relative py-2"
        >
          <span
            aria-hidden="true"
            class="absolute -left-[1.3rem] top-5 h-2 w-2 rounded-full"
            :class="i.source === 'Decision' ? 'bg-success' : i.source === 'Payment' ? 'bg-warning' : i.source === 'Activity' ? 'bg-brand' : 'bg-muted'"
          />
          <RouterLink
            v-if="i.link"
            :to="i.link"
            class="block min-h-11 rounded-lg px-2 py-1 focus-ring hover:bg-surface-subtle [overflow-wrap:anywhere]"
          >
            <span
              class="block text-card-heading font-semibold"
              :class="i.done || i.past ? 'text-ink-soft' : 'text-ink'"
            >{{ i.label }}</span>
            <span class="mt-1 block text-meta text-muted"><time :datetime="i.stamp">{{ i.allDay ? 'All day' : i.time || '00:00' }}</time> · {{ i.source }} · {{ i.past ? 'Past' : 'Upcoming' }}<span
              v-if="i.overdue"
              class="text-warning"
            > · Overdue</span><span v-else-if="i.status && i.status !== (i.past ? 'Past' : 'Upcoming')"> · {{ i.schedule || i.source === 'Decision' ? i.status : userFacingActivityStatus(i.status) }}</span><span v-else-if="i.done"> · {{ i.doneLabel }}</span></span>
          </RouterLink>
          <div
            v-else
            class="px-2 py-1 [overflow-wrap:anywhere]"
          >
            <p class="text-card-heading font-medium">
              {{ i.label }}
            </p><p class="mt-1 text-meta text-muted">
              <time :datetime="i.stamp">{{ i.allDay ? 'All day' : i.time || '00:00' }}</time> · {{ i.source }} · {{ i.past ? 'Past' : 'Upcoming' }}
            </p>
          </div>
        </li>
      </ol>
    </section>
  </div>
</template>

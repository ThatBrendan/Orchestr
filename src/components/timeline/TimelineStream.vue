<script setup lang="ts">
import { paymentScheduleLabels } from "@/lib/paymentSchedules";
import { computed } from "vue";
import { RouterLink } from "vue-router";
import AppIcon from "@/components/ui/AppIcon.vue";
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
  iso: string;
  month: string;
  date: string;
  items: Item[];
}

const groups = computed<Group[]>(() => {
  const now = Date.now();
  const byDay = new Map<string, Group>();
  for (const e of props.events.filter(e=>e.subject_type!=='milestone')) {
    const day = DateTime.fromISO(e.occurs_at, { zone: props.timezone }).toFormat('cccc d LLL yyyy');
    if (!byDay.has(day)) {
      const date = DateTime.fromISO(e.occurs_at, { zone: props.timezone });
      byDay.set(day, { day, iso: date.toISODate()!, month: date.toFormat("LLL"), date: date.toFormat("d"), items: [] });
    }
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
// Partition the already ordered projection without changing source timestamps or ordering.
const sections = computed(() => [
  { title: "Upcoming", past: false, empty: "Nothing coming up yet." },
  { title: "Recent", past: true, empty: "No recent events yet." },
].map(section => ({
  ...section,
  groups: groups.value.map(group => ({ ...group, items: group.items.filter(item => item.past === section.past) })).filter(group => group.items.length),
})));
</script>

<template>
  <div class="space-y-10">
    <section
      v-for="section in sections"
      :key="section.title"
      :aria-label="section.title"
      :class="section.past ? 'border-t border-line pt-8' : ''"
    >
      <h3
        class="mb-5 font-semibold"
        :class="section.past ? 'text-card-heading text-ink-soft' : 'text-section-heading text-ink'"
      >
        {{ section.title }}
      </h3>
      <p
        v-if="!section.groups.length"
        class="text-body text-muted py-3"
      >
        {{ section.empty }}
      </p>
      <div
        v-else
        class="space-y-6"
      >
        <section
          v-for="g in section.groups"
          :key="g.iso"
          :aria-label="g.day"
          class="flex gap-3 sm:gap-5"
        >
          <div
            aria-hidden="true"
            class="w-12 shrink-0 pt-1 text-center"
          >
            <div class="text-meta uppercase text-muted">
              {{ g.month }}
            </div>
            <div
              class="text-section-heading font-semibold"
              :class="section.past ? 'text-ink-soft' : 'text-ink'"
            >
              {{ g.date }}
            </div>
          </div>
          <div class="min-w-0 flex-1">
            <h4 class="mb-3 text-meta font-medium text-muted">
              <time :datetime="g.iso">{{ g.day }}</time>
            </h4>
            <ol class="border-l border-line pl-3 sm:pl-5 space-y-3">
              <li
                v-for="(i, idx) in g.items"
                :key="idx"
                class="relative"
              >
                <span
                  aria-hidden="true"
                  class="absolute -left-[17px] sm:-left-[25px] top-6 h-2 w-2 rounded-full"
                  :class="i.source === 'Decision' ? 'bg-success' : i.source === 'Payment' ? 'bg-warning' : i.source === 'Activity' ? 'bg-brand' : 'bg-muted'"
                />
                <component
                  :is="i.link ? RouterLink : 'div'"
                  :to="i.link ?? undefined"
                  :aria-description="i.link ? g.day + ', ' + timezone : undefined"
                  class="block min-h-11 rounded-xl p-3 sm:p-4 [overflow-wrap:anywhere]"
                  :class="[section.past ? 'bg-surface-subtle' : 'border border-line bg-surface', i.link ? 'focus-ring hover:bg-surface-subtle' : '']"
                >
                  <div class="flex items-center gap-2 text-meta">
                    <span
                      class="inline-flex items-center gap-1.5"
                      :class="i.source === 'Decision' ? 'text-success' : i.source === 'Payment' ? 'text-warning' : i.source === 'Activity' ? 'text-brand' : 'text-muted'"
                    >
                      <AppIcon
                        :name="i.source === 'Decision' ? 'flag' : i.source === 'Payment' ? 'coins' : i.source === 'Activity' ? 'checkCircle' : 'calendar'"
                        :size="16"
                      />
                      {{ i.source }}
                    </span>
                    <span class="text-muted">·</span>
                    <time
                      :datetime="i.stamp"
                      class="text-muted"
                    >{{ i.allDay ? 'All day' : i.time || '00:00' }}</time>
                  </div>
                  <p
                    class="mt-2 text-card-heading font-semibold"
                    :class="i.done || i.past ? 'text-ink-soft' : 'text-ink'"
                  >
                    {{ i.label }}
                  </p>
                  <p
                    v-if="i.overdue || i.status || i.done"
                    class="mt-1 text-meta"
                    :class="i.overdue ? 'text-warning' : 'text-muted'"
                  >
                    {{ i.overdue ? 'Overdue' : i.status ? (i.schedule || i.source === 'Decision' ? i.status : userFacingActivityStatus(i.status)) : i.doneLabel }}
                  </p>
                  <span
                    v-if="i.link"
                    class="mt-3 inline-flex items-center gap-1.5 text-meta"
                    :class="section.past ? 'text-ink-soft' : 'text-brand'"
                  >
                    {{ i.source === 'Decision' ? 'Open decision' : i.source === 'Payment' ? 'Open payments' : 'Open Activity' }}
                    <span aria-hidden="true">→</span>
                  </span>
                </component>
              </li>
            </ol>
          </div>
        </section>
      </div>
    </section>
  </div>
</template>

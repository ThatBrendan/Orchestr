<script setup lang="ts">
import { computed } from "vue";
import type { TimelineEvent } from "@/types/derived";
import { useProjectTime } from "@/composables/useProjectTime";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import { presentLabel } from "@/lib/presentation";

const props = defineProps<{ events: TimelineEvent[]; timezone: string }>();
const t = computed(() => useProjectTime(props.timezone));

// "Completed items" (BUSINESS_RULES §Timeline): a resolved commitment/payment is shown
// muted rather than looking identical to something still pending. "Upcoming deadlines"
// that have slipped into the past while still open (a due payment/task) are flagged —
// this is a purely visual read of already-derived fields, not a second health engine.
const DONE_STATUSES = new Set(["completed", "cancelled", "paid", "skipped"]);
const DEADLINE_TYPES = new Set(["payment_due", "task_due", "recurring_commitment_due", "recurring_task_due"]);

interface Item {
  label: string;
  status: string | null;
  link: { name: string; params: { projectId: string }; query: { commitment: string; occurrence: string } } | null;
  time: string;
  allDay: boolean;
  done: boolean;
  overdue: boolean;
}
interface Group {
  day: string;
  items: Item[];
}

const groups = computed<Group[]>(() => {
  const now = Date.now();
  const byDay = new Map<string, Group>();
  for (const e of props.events) {
    const day = t.value.dayLabel(e.occurs_at);
    if (!byDay.has(day)) byDay.set(day, { day, items: [] });
    const done = !!e.status && DONE_STATUSES.has(e.status);
    const isPast = new Date(e.occurs_at).getTime() < now;
    byDay.get(day)!.items.push({
      label: e.title,
      status: e.is_recurring_occurrence ? e.status : null,
      link: e.subject_type === "commitment" && e.occurrence_date ? { name: "project.commitments", params: { projectId: e.project_id }, query: { commitment: e.subject_id, occurrence: e.occurrence_date } } : null,
      time: e.all_day ? "" : t.value.time(e.occurs_at),
      allDay: e.all_day,
      done,
      overdue: e.is_recurring_occurrence ? e.status === "overdue" : !done && isPast && DEADLINE_TYPES.has(e.event_type),
    });
  }
  return [...byDay.values()];
});
</script>

<template>
  <div class="mt-3 border rounded-xl divide-y border-line bg-surface">
    <div
      v-for="g in groups"
      :key="g.day"
      class="px-4 py-3.5"
    >
      <div class="text-[12.5px] font-medium mb-2 text-muted">
        {{ g.day }}
      </div>
      <div class="space-y-2">
        <div
          v-for="(i, idx) in g.items"
          :key="idx"
          class="flex items-center gap-3 text-14"
          :class="i.done ? 'text-muted' : ''"
        >
          <span
            class="tnum w-12 shrink-0"
            :class="i.overdue ? 'text-danger font-medium' : 'text-ink-soft'"
          >
            {{ i.allDay ? "All day" : i.time }}
          </span>
          <RouterLink
            v-if="i.link"
            :to="i.link"
            class="focus-ring hover:underline"
          >
            {{ i.label }}
          </RouterLink>
          <span
            v-else
            :class="i.done ? 'line-through' : ''"
          >{{ i.label }}</span>
          <StatusBadge
            v-if="i.status && !i.overdue"
            :label="presentLabel(i.status)"
            tone="neutral"
            class="capitalize"
          />
          <StatusBadge
            v-if="i.overdue"
            label="Overdue"
            tone="danger"
          />
        </div>
      </div>
    </div>
  </div>
</template>

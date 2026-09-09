<script setup lang="ts">
import { computed, ref } from "vue";
import { DateTime } from "luxon";
import { RouterLink } from "vue-router";
import { useGlobalCalendar } from "@/composables/useGlobalCalendar";
import { useMyProjects } from "@/composables/useProjects";
import { useMyProfile } from "@/composables/useDashboard";
import { useMoney } from "@/composables/useMoney";
import type { GlobalTimelineEvent } from "@/types/derived";
import PageContainer from "@/components/ui/PageContainer.vue";
import AppButton from "@/components/ui/AppButton.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";

const { profile } = useMyProfile();
const { projects } = useMyProjects();
const { format } = useMoney();

const zone = computed(() => profile.value?.timezone ?? "UTC");
const selectedMonth = ref(DateTime.now().setZone(zone.value).startOf("month"));
const selectedProject = ref("");
const selectedType = ref("");

const queryStart = computed(() => selectedMonth.value.minus({ days: 2 }).toUTC().toISO() ?? "");
const queryEnd = computed(() => selectedMonth.value.endOf("month").plus({ days: 2 }).toUTC().toISO() ?? "");
const calendar = useGlobalCalendar(queryStart, queryEnd);

const monthLabel = computed(() => selectedMonth.value.toFormat("LLLL yyyy"));
const eventTypes = computed(() => Array.from(new Set(calendar.events.value.map((e) => e.event_type))).sort());

function eventDayKey(event: GlobalTimelineEvent): string {
  return DateTime.fromISO(event.occurs_at, { zone: event.project_timezone }).toISODate() ?? "";
}

const filteredEvents = computed(() =>
  calendar.events.value
    .filter((event) => eventDayKey(event).startsWith(selectedMonth.value.toFormat("yyyy-LL")))
    .filter((event) => !selectedProject.value || event.project_id === selectedProject.value)
    .filter((event) => !selectedType.value || event.event_type === selectedType.value),
);

const eventsByDay = computed(() => {
  const map = new Map<string, GlobalTimelineEvent[]>();
  for (const event of filteredEvents.value) {
    const key = eventDayKey(event);
    map.set(key, [...(map.get(key) ?? []), event]);
  }
  return map;
});

const monthDays = computed(() => {
  const start = selectedMonth.value.startOf("month");
  const firstGridDay = start.minus({ days: start.weekday - 1 });
  return Array.from({ length: 42 }, (_, index) => {
    const day = firstGridDay.plus({ days: index });
    const key = day.toISODate() ?? "";
    return { day, key, inMonth: day.month === selectedMonth.value.month };
  });
});

function moveMonth(delta: number) {
  selectedMonth.value = selectedMonth.value.plus({ months: delta }).startOf("month");
}

function goToday() {
  selectedMonth.value = DateTime.now().setZone(zone.value).startOf("month");
}

function typeLabel(type: string): string {
  return type.replace(/_/g, " ");
}

function statusTone(status: string | null) {
  if (status === "completed" || status === "paid" || status === "booked") return "accent";
  if (status === "cancelled" || status === "waived") return "neutral";
  return "amber";
}

function eventRoute(event: GlobalTimelineEvent) {
  if (event.subject_type === "commitment") {
    return {
      name: "project.commitments",
      params: { projectId: event.project_id },
      query: {
        commitment: event.subject_id,
        ...(event.occurrence_date ? { occurrence: event.occurrence_date } : {}),
      },
    };
  }
  if (event.subject_type === "payment") return { name: "project.budget", params: { projectId: event.project_id } };
  if (event.subject_type === "task") return { name: "project.commitments", params: { projectId: event.project_id } };
  if (event.subject_type === "milestone") return { name: "project.timeline", params: { projectId: event.project_id } };
  return { name: "project.overview", params: { projectId: event.project_id } };
}

function eventTime(event: GlobalTimelineEvent): string | null {
  if (event.all_day) return null;
  return DateTime.fromISO(event.occurs_at, { zone: event.project_timezone }).toFormat("HH:mm");
}

function isPast(event: GlobalTimelineEvent): boolean {
  return DateTime.fromISO(event.occurs_at) < DateTime.now() && !["completed", "paid", "booked"].includes(event.status ?? "");
}
</script>

<template>
  <PageContainer width="lg">
    <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">Calendar</h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">All deadlines, bookings and payments across your projects.</p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <AppButton variant="secondary" size="sm" @click="moveMonth(-1)">Previous month</AppButton>
        <AppButton variant="secondary" size="sm" @click="goToday">Today</AppButton>
        <AppButton variant="secondary" size="sm" @click="moveMonth(1)">Next month</AppButton>
      </div>
    </div>

    <div class="mt-6 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
      <h2 class="font-display text-[22px] font-semibold tracking-tight">{{ monthLabel }}</h2>
      <div class="grid gap-2 sm:grid-cols-2 md:w-[28rem]">
        <select v-model="selectedProject" class="border rounded-lg px-3 py-2 text-14 focus-ring border-line bg-surface">
          <option value="">All projects</option>
          <option v-for="project in projects" :key="project.project_id" :value="project.project_id">{{ project.name }}</option>
        </select>
        <select v-model="selectedType" class="border rounded-lg px-3 py-2 text-14 capitalize focus-ring border-line bg-surface">
          <option value="">All event types</option>
          <option v-for="type in eventTypes" :key="type" :value="type">{{ typeLabel(type) }}</option>
        </select>
      </div>
    </div>

    <div v-if="calendar.isPending.value" class="mt-5 grid gap-2 md:grid-cols-7">
      <SkeletonBlock v-for="i in 14" :key="i" height="96px" rounded="0.5rem" />
    </div>
    <ErrorState v-else-if="calendar.isError.value" class="mt-5" :error="calendar.error.value" :retry="() => calendar.refetch()" />
    <EmptyState
      v-else-if="calendar.events.value.length === 0"
      class="mt-5"
      message="Nothing scheduled yet. Dates, deadlines, bookings and payments from your projects will appear here."
    />
    <template v-else>
      <EmptyState v-if="filteredEvents.length === 0" class="mt-5" message="Nothing scheduled this month." />

      <div class="mt-5 hidden overflow-hidden rounded-xl border border-line bg-surface md:grid md:grid-cols-7">
        <div
          v-for="label in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']"
          :key="label"
          class="border-b border-line px-3 py-2 text-12 font-semibold uppercase text-muted"
        >
          {{ label }}
        </div>
        <div
          v-for="cell in monthDays"
          :key="cell.key"
          class="min-h-[8.5rem] border-b border-r border-line p-2 last:border-r-0"
          :class="cell.inMonth ? 'bg-surface' : 'bg-[#FBFBFA] text-muted'"
        >
          <div class="text-12 font-medium">{{ cell.day.day }}</div>
          <div class="mt-2 space-y-1.5">
            <RouterLink
              v-for="event in eventsByDay.get(cell.key) ?? []"
              :key="event.event_type + event.subject_id + event.occurs_at + (event.occurrence_date ?? '')"
              :to="eventRoute(event)"
              class="block rounded-md border border-line px-2 py-1.5 text-12 hover:bg-[#F6F6F4] focus-ring"
            >
              <div class="font-medium truncate">{{ event.title }}</div>
              <div class="mt-0.5 truncate text-muted">{{ event.project_name }}</div>
              <div class="mt-1 flex items-center gap-1.5">
                <span class="capitalize text-muted">{{ typeLabel(event.event_type) }}</span>
                <span v-if="eventTime(event)" class="text-muted">{{ eventTime(event) }}</span>
                <span v-if="event.amount_minor != null" class="font-medium">{{ format(event.amount_minor, event.currency) }}</span>
              </div>
            </RouterLink>
          </div>
        </div>
      </div>

      <div class="mt-5 space-y-2 md:hidden">
        <RouterLink
          v-for="event in filteredEvents"
          :key="event.event_type + event.subject_id + event.occurs_at + (event.occurrence_date ?? '')"
          :to="eventRoute(event)"
          class="block rounded-xl border border-line bg-surface p-4 focus-ring"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="text-13 font-medium text-muted">
                {{ DateTime.fromISO(event.occurs_at, { zone: event.project_timezone }).toFormat("d LLL") }}
              </div>
              <div class="mt-1 text-14 font-medium">{{ event.title }}</div>
              <div class="mt-0.5 text-13 text-muted">{{ event.project_name }}</div>
            </div>
            <StatusBadge v-if="isPast(event)" label="Overdue" tone="amber" />
            <StatusBadge v-else-if="event.status" :label="event.status" :tone="statusTone(event.status)" />
          </div>
          <div class="mt-2 flex flex-wrap gap-2 text-13 text-muted">
            <span class="capitalize">{{ typeLabel(event.event_type) }}</span>
            <span v-if="eventTime(event)">{{ eventTime(event) }}</span>
            <span v-if="event.amount_minor != null" class="font-medium text-ink-soft">{{ format(event.amount_minor, event.currency) }}</span>
          </div>
        </RouterLink>
      </div>
    </template>
  </PageContainer>
</template>

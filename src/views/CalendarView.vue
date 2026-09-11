<script setup lang="ts">
import { computed, ref } from "vue";
import { DateTime } from "luxon";
import { RouterLink } from "vue-router";
import { useGlobalCalendar } from "@/composables/useGlobalCalendar";
import { useMyProjects } from "@/composables/useProjects";
import { useMyProfile } from "@/composables/useDashboard";
import { useMoney } from "@/composables/useMoney";
import { CALENDAR_SEMANTICS, calendarPresentation, calendarTypeLabel } from "@/lib/calendarPresentation";
import type { GlobalTimelineEvent } from "@/types/derived";
import PageContainer from "@/components/ui/PageContainer.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppModal from "@/components/ui/AppModal.vue";
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
const selectedDay = ref<string | null>(null);
const VISIBLE_MARKERS = 3;

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
  return calendarTypeLabel(type);
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

function eventDate(event: GlobalTimelineEvent): string {
  return DateTime.fromISO(event.occurs_at, { zone: event.project_timezone }).toFormat("d LLL yyyy");
}

function eventKey(event: GlobalTimelineEvent): string {
  return event.event_type + event.subject_id + event.occurs_at + (event.occurrence_date ?? "");
}

function eventAccessibleLabel(event: GlobalTimelineEvent): string {
  const presentation = calendarPresentation(event.event_type);
  const amount = event.amount_minor != null ? `, ${format(event.amount_minor, event.currency)}` : "";
  return `${presentation.label}: ${event.title}, ${event.project_name}, ${eventDate(event)}${event.is_recurring_occurrence ? `, ${event.status}` : ""}${amount}`;
}

function eventStatusClass(event: GlobalTimelineEvent): string {
  if (["completed", "paid", "booked", "cancelled", "waived", "skipped"].includes(event.status ?? "")) {
    return "opacity-50 grayscale";
  }
  if (event.status === "overdue" || isPast(event)) return "ring-1 ring-amber-400";
  return "";
}

function eventsForDay(key: string): GlobalTimelineEvent[] {
  return eventsByDay.value.get(key) ?? [];
}

const selectedDayEvents = computed(() => (selectedDay.value ? eventsForDay(selectedDay.value) : []));
const selectedDayLabel = computed(() =>
  selectedDay.value ? DateTime.fromISO(selectedDay.value, { zone: zone.value }).toFormat("d LLLL yyyy") : "",
);

function openDayAgenda(day: string) {
  selectedDay.value = day;
}

function isPast(event: GlobalTimelineEvent): boolean {
  if (event.is_recurring_occurrence) return event.status === "overdue";
  return DateTime.fromISO(event.occurs_at) < DateTime.now() && !["completed", "paid", "booked"].includes(event.status ?? "");
}
</script>

<template>
  <PageContainer width="lg">
    <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">
          Calendar
        </h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">
          All deadlines, bookings and payments across your projects.
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <AppButton
          variant="secondary"
          size="sm"
          @click="moveMonth(-1)"
        >
          Previous month
        </AppButton>
        <AppButton
          variant="secondary"
          size="sm"
          @click="goToday"
        >
          Today
        </AppButton>
        <AppButton
          variant="secondary"
          size="sm"
          @click="moveMonth(1)"
        >
          Next month
        </AppButton>
      </div>
    </div>

    <div class="mt-6 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
      <h2 class="font-display text-[22px] font-semibold tracking-tight">
        {{ monthLabel }}
      </h2>
      <div class="grid gap-2 sm:grid-cols-2 md:w-[28rem]">
        <select
          v-model="selectedProject"
          class="border rounded-lg px-3 py-2 text-14 focus-ring border-line bg-surface"
        >
          <option value="">
            All projects
          </option>
          <option
            v-for="project in projects"
            :key="project.project_id"
            :value="project.project_id"
          >
            {{ project.name }}
          </option>
        </select>
        <select
          v-model="selectedType"
          class="border rounded-lg px-3 py-2 text-14 capitalize focus-ring border-line bg-surface"
        >
          <option value="">
            All event types
          </option>
          <option
            v-for="type in eventTypes"
            :key="type"
            :value="type"
          >
            {{ typeLabel(type) }}
          </option>
        </select>
      </div>
    </div>

    <div
      class="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-12 text-muted"
      aria-label="Calendar legend"
    >
      <span
        v-for="semantic in CALENDAR_SEMANTICS"
        :key="semantic.semantic"
        class="inline-flex items-center gap-1.5"
      >
        <span
          class="inline-flex h-5 w-5 items-center justify-center rounded border"
          :class="semantic.markerClass"
        >
          <AppIcon
            :name="semantic.icon"
            :size="12"
          />
        </span>
        {{ semantic.label }}
      </span>
    </div>

    <div
      v-if="calendar.isPending.value"
      class="mt-5 grid gap-2 md:grid-cols-7"
    >
      <SkeletonBlock
        v-for="i in 14"
        :key="i"
        height="96px"
        rounded="0.5rem"
      />
    </div>
    <ErrorState
      v-else-if="calendar.isError.value"
      class="mt-5"
      :error="calendar.error.value"
      :retry="() => calendar.refetch()"
    />
    <EmptyState
      v-else-if="calendar.events.value.length === 0"
      class="mt-5"
      message="Nothing scheduled yet. Dates, deadlines, bookings and payments from your projects will appear here."
    />
    <template v-else>
      <EmptyState
        v-if="filteredEvents.length === 0"
        class="mt-5"
        message="Nothing scheduled this month."
      />

      <div class="mt-5 hidden rounded-xl border border-line bg-surface md:grid md:grid-cols-7">
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
          <div class="text-12 font-medium">
            {{ cell.day.day }}
          </div>
          <div class="mt-2 flex min-h-12 flex-wrap content-start gap-1">
            <RouterLink
              v-for="event in eventsForDay(cell.key).slice(0, VISIBLE_MARKERS)"
              :key="eventKey(event)"
              :to="eventRoute(event)"
              class="group relative inline-flex h-8 w-8 items-center justify-center rounded-md border focus-ring hover:brightness-95"
              :class="[calendarPresentation(event.event_type).markerClass, eventStatusClass(event)]"
              :aria-label="eventAccessibleLabel(event)"
              :title="eventAccessibleLabel(event)"
            >
              <AppIcon
                :name="calendarPresentation(event.event_type).icon"
                :size="16"
              />
              <span class="pointer-events-none absolute left-0 top-9 z-30 hidden w-56 rounded-lg border border-line bg-surface p-2.5 text-left text-12 shadow-lg group-hover:block group-focus:block">
                <span class="block font-medium text-ink">{{ event.title }}</span>
                <span class="mt-0.5 block text-muted">{{ event.project_name }}</span>
                <span
                  class="mt-1 block"
                  :class="calendarPresentation(event.event_type).softClass"
                >
                  {{ typeLabel(event.event_type) }} · {{ eventDate(event) }}
                </span>
              </span>
            </RouterLink>
            <button
              v-if="eventsForDay(cell.key).length > VISIBLE_MARKERS"
              type="button"
              class="h-8 rounded-md px-1.5 text-12 font-semibold text-ink-soft hover:bg-paper focus-ring"
              :aria-label="`Show all ${eventsForDay(cell.key).length} events for ${cell.day.toFormat('d LLLL yyyy')}`"
              @click="openDayAgenda(cell.key)"
            >
              +{{ eventsForDay(cell.key).length - VISIBLE_MARKERS }} more
            </button>
          </div>
        </div>
      </div>

      <div class="mt-5 space-y-2 md:hidden">
        <RouterLink
          v-for="event in filteredEvents"
          :key="eventKey(event)"
          :to="eventRoute(event)"
          class="block rounded-xl border border-line bg-surface p-4 focus-ring"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="text-13 font-medium text-muted">
                {{ DateTime.fromISO(event.occurs_at, { zone: event.project_timezone }).toFormat("d LLL") }}
              </div>
              <div class="mt-1 text-14 font-medium">
                {{ event.title }}
              </div>
              <div class="mt-0.5 text-13 text-muted">
                {{ event.project_name }}
              </div>
            </div>
            <StatusBadge
              v-if="isPast(event)"
              label="Overdue"
              tone="amber"
            />
            <StatusBadge
              v-else-if="event.status"
              :label="event.status"
              :tone="statusTone(event.status)"
            />
          </div>
          <div class="mt-2 flex flex-wrap gap-2 text-13 text-muted">
            <span
              class="inline-flex items-center gap-1"
              :class="calendarPresentation(event.event_type).softClass"
            >
              <AppIcon
                :name="calendarPresentation(event.event_type).icon"
                :size="14"
              />
              {{ typeLabel(event.event_type) }}
            </span>
            <span v-if="eventTime(event)">{{ eventTime(event) }}</span>
            <span
              v-if="event.amount_minor != null"
              class="font-medium text-ink-soft"
            >{{ format(event.amount_minor, event.currency) }}</span>
          </div>
        </RouterLink>
      </div>
    </template>

    <AppModal
      :open="!!selectedDay"
      :title="selectedDayLabel"
      size="lg"
      @close="selectedDay = null"
    >
      <div class="space-y-2">
        <RouterLink
          v-for="event in selectedDayEvents"
          :key="eventKey(event)"
          :to="eventRoute(event)"
          class="flex items-start gap-3 rounded-lg border border-line p-3 hover:bg-paper focus-ring"
          :class="eventStatusClass(event)"
          :aria-label="eventAccessibleLabel(event)"
          @click="selectedDay = null"
        >
          <span
            class="mt-0.5 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-md border"
            :class="calendarPresentation(event.event_type).markerClass"
          >
            <AppIcon
              :name="calendarPresentation(event.event_type).icon"
              :size="16"
            />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-14 font-medium">{{ event.title }}</span>
            <span class="mt-0.5 block text-13 text-muted">{{ event.project_name }}</span>
            <span
              class="mt-1 block text-13"
              :class="calendarPresentation(event.event_type).softClass"
            >
              {{ typeLabel(event.event_type) }}<span v-if="event.occurrence_date"> · Recurring · <span class="capitalize">{{ event.status }}</span></span>
              <span v-if="event.amount_minor != null"> · {{ format(event.amount_minor, event.currency) }}</span>
            </span>
          </span>
        </RouterLink>
      </div>
    </AppModal>
  </PageContainer>
</template>

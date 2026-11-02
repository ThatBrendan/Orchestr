<script setup lang="ts">
import { computed, ref } from 'vue';
import { DateTime } from 'luxon';
import { useMediaQuery, useNow } from '@vueuse/core';
import { useGlobalCalendar } from '@/composables/useGlobalCalendar';
import { useMyProjects } from '@/composables/useProjects';
import { useMyProfile } from '@/composables/useDashboard';
import { globalEventDay, globalEventKey, globalEventSource, globalEventTypeLabel } from '@/lib/globalCalendarPresentation';
import type { GlobalTimelineEvent } from '@/types/derived';
import PageContainer from '@/components/ui/PageContainer.vue';
import AppIcon from '@/components/ui/AppIcon.vue';
import ErrorState from '@/components/ui/ErrorState.vue';
import CalendarToolbar from '@/components/calendar/CalendarToolbar.vue';
import CalendarMonthGrid from '@/components/calendar/CalendarMonthGrid.vue';
import CalendarLoading from '@/components/calendar/CalendarLoading.vue';
import GlobalCalendarEventLink from '@/components/calendar/GlobalCalendarEventLink.vue';

const { profile } = useMyProfile();
const { projects } = useMyProjects();
const zone = computed(() => profile.value?.timezone ?? 'UTC');
// Preserve the global query's existing month anchor and two-day buffer.
const selectedMonth = ref(DateTime.now().setZone(zone.value).startOf('month'));
const selectedProject = ref('');
const selectedType = ref('');
const selectedDay = ref<string | null>(null);
const queryStart = computed(() => selectedMonth.value.minus({days: 2}).toUTC().toISO() ?? '');
const queryEnd = computed(() => selectedMonth.value.endOf('month').plus({days: 2}).toUTC().toISO() ?? '');
const calendar = useGlobalCalendar(queryStart, queryEnd);
const monthLabel = computed(() => selectedMonth.value.toFormat('LLLL yyyy'));
const eventTypes = computed(() => Array.from(new Set(calendar.events.value.map(e => e.event_type))).sort().map(type => ({
  type, label: globalEventTypeLabel(type), source: globalEventSource(calendar.events.value.find(e => e.event_type === type)!.subject_type),
})));
const now = useNow({interval: 60_000});
const today = computed(() => DateTime.fromJSDate(now.value, {zone: zone.value}).toISODate()!);
const narrow = useMediaQuery('(max-width: 639px)');
const compactMonth = useMediaQuery('(max-width: 1023px)');
const selectedView = ref<'month' | 'agenda' | null>(null);
const view = computed(() => selectedView.value ?? (narrow.value ? 'agenda' : 'month'));
const entries = computed(() => calendar.events.value
  .filter(e => globalEventDay(e).startsWith(selectedMonth.value.toFormat('yyyy-LL')))
  .filter(e => !selectedProject.value || e.project_id === selectedProject.value)
  .filter(e => !selectedType.value || e.event_type === selectedType.value));
const eventsByDay = computed(() => {
  const map = new Map<string, GlobalTimelineEvent[]>();
  for (const event of entries.value) {
    const key = globalEventDay(event);
    map.set(key, [...(map.get(key) ?? []), event]);
  }
  return map;
});
const days = computed(() => {
  const start = selectedMonth.value.startOf('month');
  const first = start.minus({days: start.weekday - 1});
  return Array.from({length: 42}, (_, index) => {
    const date = first.plus({days: index});
    const key = date.toISODate()!;
    return {key, date, entries: eventsByDay.value.get(key) ?? []};
  });
});
const weeks = computed(() => Array.from({length: 6}, (_, i) => days.value.slice(i * 7, i * 7 + 7)));
const selected = computed(() => days.value.find(d => d.key === selectedDay.value));
const agenda = computed(() => days.value.filter(d => selectedDay.value ? d.key === selectedDay.value : d.entries.length));
const comingUp = computed(() => entries.value.filter(e => globalEventDay(e) >= DateTime.fromJSDate(now.value, {zone: e.project_timezone}).toISODate()!).slice(0, 3));
function move(delta: number) {selectedMonth.value = selectedMonth.value.plus({months: delta}).startOf('month'); selectedDay.value = null;}
function goToday() {selectedMonth.value = DateTime.now().setZone(zone.value).startOf('month'); selectedDay.value = null;}
function selectDay(day: string) {selectedDay.value = day;}
</script>

<template>
  <PageContainer width="lg">
    <section
      class="space-y-5 min-w-0"
      aria-label="Cross-project calendar"
    >
      <header>
        <h1 class="font-display text-page-title font-semibold tracking-tight">
          Calendar
        </h1>
        <p class="mt-1 text-sm text-ink-soft">
          Activities and deadlines across your projects.
        </p>
        <p class="mt-1 text-meta text-muted">
          Dates and times follow each event’s project timezone.
        </p>
      </header>
      <div class="space-y-3">
        <div
          class="flex gap-2 overflow-x-auto pb-1 lg:flex-wrap"
          role="group"
          aria-label="Calendar event types"
        >
          <button
            class="focus-ring calendar-button calendar-filter inline-flex shrink-0 whitespace-nowrap items-center gap-2"
            :aria-pressed="selectedType === ''"
            @click="selectedType = ''"
          >
            <AppIcon
              name="calendar"
              :size="16"
            />All
          </button>
          <button
            v-for="item in eventTypes"
            :key="item.type"
            class="focus-ring calendar-button calendar-filter inline-flex shrink-0 whitespace-nowrap items-center gap-2"
            :aria-pressed="selectedType === item.type"
            @click="selectedType = item.type"
          >
            <AppIcon
              :name="item.source.icon"
              :size="16"
              :class="item.source.text"
            />{{ item.label }}
          </button>
        </div>
        <select
          v-model="selectedProject"
          aria-label="Filter calendar by project"
          class="min-h-11 min-w-0 w-full sm:max-w-xs border rounded-lg px-3 py-2 text-sm focus-ring border-line bg-surface"
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
      </div>
      <CalendarToolbar
        :heading-level="2"
        :label="monthLabel"
        :view="view"
        @previous="move(-1)"
        @next="move(1)"
        @today="goToday"
        @update:view="selectedView = $event"
      />
      <CalendarLoading
        v-if="calendar.isPending.value"
        :view="view"
      />
      <ErrorState
        v-else-if="calendar.isError.value"
        :error="calendar.error.value"
        :retry="() => calendar.refetch()"
      />
      <template v-else>
        <p
          v-if="!entries.length"
          class="text-sm text-muted"
        >
          {{ !selectedType && !selectedProject ? 'Nothing scheduled this month.' : 'No matching items this month.' }}
        </p>
        <div
          v-if="view === 'month'"
          class="calendar-layout"
        >
          <div class="min-w-0">
            <CalendarMonthGrid
              :weeks="weeks"
              :anchor-month="selectedMonth.month"
              :today="today"
              :selected-day="selectedDay"
              :compact-month="compactMonth"
              :entry-key="globalEventKey"
              roomy
              @select="selectDay"
            >
              <template #entry="{entry}">
                <GlobalCalendarEventLink
                  :event="entry"
                  compact
                />
              </template>
            </CalendarMonthGrid>
          </div>
          <div class="min-w-0 space-y-5">
            <section
              class="rounded-xl border border-line bg-surface"
              aria-label="Selected day"
              aria-live="polite"
            >
              <div class="p-4 sm:p-5 border-b border-line">
                <p class="text-xs uppercase tracking-wider font-semibold text-brand">
                  Selected day
                </p>
                <h3 class="mt-2 text-base font-semibold">
                  {{ selected ? selected.date.toFormat('cccc, d LLLL yyyy') + (selected.key === today ? ' · Today' : '') : 'A closer look at your day' }}
                </h3>
                <p
                  v-if="!selected"
                  class="mt-2 text-sm text-muted"
                >
                  Choose a date in the month to see what’s scheduled.
                </p>
                <button
                  v-if="selectedDay"
                  class="focus-ring mt-2 min-h-11 text-sm text-brand"
                  @click="selectedDay = null"
                >
                  Show all dates
                </button>
              </div>
              <ul
                v-if="selected?.entries.length"
                class="divide-y divide-line"
              >
                <li
                  v-for="entry in selected.entries"
                  :key="globalEventKey(entry)"
                >
                  <GlobalCalendarEventLink
                    :event="entry"
                  />
                </li>
              </ul>
              <p
                v-else-if="selected"
                class="p-5 text-sm text-muted"
              >
                Nothing scheduled for this day.
              </p>
            </section>
            <section
              v-if="comingUp.length"
              class="rounded-xl border border-line bg-surface"
              aria-label="Coming up"
            >
              <div class="p-4 border-b border-line">
                <h3 class="text-sm font-semibold">
                  Coming up
                </h3><p class="mt-1 text-meta text-muted">
                  Next dated items in this displayed range.
                </p>
              </div>
              <ul class="divide-y divide-line">
                <li
                  v-for="entry in comingUp"
                  :key="globalEventKey(entry)"
                  class="p-3"
                >
                  <p class="mb-2 text-meta font-medium text-ink-soft">
                    {{ DateTime.fromISO(globalEventDay(entry), { zone: zone }).toFormat('ccc d LLL') }}
                  </p>
                  <GlobalCalendarEventLink
                    :event="entry"

                    compact
                  />
                </li>
              </ul>
            </section>
          </div>
        </div>
        <div
          v-else
          class="space-y-5"
          aria-live="polite"
        >
          <button
            v-if="selectedDay"
            class="focus-ring calendar-button"
            @click="selectedDay = null"
          >
            Show all dates
          </button>
          <section
            v-for="day in agenda"
            :key="day.key"
            :aria-label="day.date.toFormat('cccc, d LLLL yyyy')"
            class="agenda-day"
          >
            <div class="flex items-center gap-3 mb-3">
              <div
                class="w-12 shrink-0 rounded-lg border border-line bg-surface py-2 text-center"
                aria-hidden="true"
              >
                <span class="block text-xs uppercase text-muted">{{ day.date.toFormat('LLL') }}</span><span class="block text-lg font-semibold">{{ day.date.day }}</span>
              </div>
              <h3 class="text-sm font-semibold">
                {{ day.date.toFormat('cccc, d LLLL yyyy') }}{{ day.key === today ? ' · Today' : '' }}
              </h3>
            </div>
            <ul
              v-if="day.entries.length"
              class="rounded-xl border border-line bg-surface divide-y divide-line"
            >
              <li
                v-for="entry in day.entries"
                :key="globalEventKey(entry)"
              >
                <GlobalCalendarEventLink
                  :event="entry"
                />
              </li>
            </ul>
            <p
              v-else
              class="text-sm text-muted"
            >
              Nothing scheduled for this day.
            </p>
          </section>
        </div>
      </template>
    </section>
  </PageContainer>
</template>

<style scoped>
.calendar-button { @apply min-h-11 rounded-lg border border-line bg-surface px-3 py-2 text-sm; }
.calendar-filter { @apply text-ink-soft; }
.calendar-button[aria-pressed="true"] { @apply bg-brand-soft text-brand border-brand/40; }
.calendar-layout { display: grid; gap: 1.25rem; min-width: 0; }
@media (min-width: 1400px) { .calendar-layout { grid-template-columns: minmax(0, 1fr) 280px; align-items: start; } }
</style>

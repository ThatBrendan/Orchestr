<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useMediaQuery, useNow } from '@vueuse/core';
import { DateTime } from 'luxon';
import { useProjectContext } from '@/composables/useProjectContext';
import { useProjectCalendar } from '@/composables/useProjectCalendar';
import { entryDay, entryOnDay } from '@/lib/executionCalendar';
import CalendarEntryLink from '@/components/calendar/CalendarEntryLink.vue';
import ErrorState from '@/components/ui/ErrorState.vue';
import SkeletonBlock from '@/components/ui/SkeletonBlock.vue';
const route = useRoute();
const { project } = useProjectContext();
const timezone = computed(() => project.value?.timezone ?? 'UTC');
const now = useNow({ interval: 60_000 });
const today = computed(() => DateTime.fromJSDate(now.value, { zone: timezone.value }).toISODate()!);
const month = ref('');
watch(timezone, () => { month.value = today.value.slice(0, 7); }, { immediate: true });
const anchor = computed(() => DateTime.fromISO(`${month.value}-01`, { zone: timezone.value }));
const start = computed(() => anchor.value.startOf('week'));
const end = computed(() => anchor.value.endOf('month').endOf('week').plus({ days: 1 }).startOf('day'));
const calendar = useProjectCalendar(computed(() => String(route.params.projectId)), computed(() => start.value.toISODate()!), computed(() => end.value.toISODate()!));
const narrow = useMediaQuery('(max-width: 639px)');
const compactMonth = useMediaQuery('(max-width: 1023px)');
const selectedView = ref<'month' | 'agenda' | null>(null);
const view = computed(() => selectedView.value ?? (narrow.value ? 'agenda' : 'month'));
const filter = ref('all');
const selectedDay = ref<string | null>(null);
const filters = [{ id: 'all', label: 'All' }, { id: 'activity', label: 'Activities' }, { id: 'decision', label: 'Decisions' }, { id: 'payment_schedule', label: 'Payments' }];
const entries = computed(() => (calendar.data.value ?? []).filter(e => filter.value === 'all' || e.source_type === filter.value || (filter.value === 'activity' && e.source_type === 'activity_occurrence')).sort((a, b) => entryDay(a, timezone.value).localeCompare(entryDay(b, timezone.value)) || (a.start_at ?? '').localeCompare(b.start_at ?? '') || a.entry_id.localeCompare(b.entry_id)));
const days = computed(() => Array.from({ length: Math.round(end.value.diff(start.value, 'days').days) }, (_, i) => {
  const date = start.value.plus({ days: i });
  const key = date.toISODate()!;
  return { key, date, entries: entries.value.filter(e => entryOnDay(e, key, timezone.value)) };
}));
const weeks = computed(() => Array.from({ length: days.value.length / 7 }, (_, i) => days.value.slice(i * 7, i * 7 + 7)));
const agenda = computed(() => days.value.filter(d => selectedDay.value ? d.key === selectedDay.value : d.entries.length));
function move(delta: number) { month.value = anchor.value.plus({ months: delta }).toFormat('yyyy-MM'); selectedDay.value = null; }
function goToday() { month.value = today.value.slice(0, 7); selectedDay.value = null; }
function selectDay(day: string) { selectedDay.value = day; }
</script>

<template>
  <section
    class="space-y-5 min-w-0 fade-in"
    aria-label="Project execution calendar"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div class="min-w-0">
        <h2
          class="text-section-heading"
          aria-live="polite"
        >
          Calendar
        </h2>
        <p class="mt-1 text-meta text-muted break-words">
          Times shown in {{ timezone }}
        </p>
      </div>
      <RouterLink
        class="min-h-11 inline-flex items-center text-sm text-brand focus-ring"
        :to="{ name: 'project.commitments', params: route.params }"
      >
        Go to Activities
      </RouterLink>
    </header>
    <div class="flex flex-wrap items-center gap-2">
      <h3
        class="w-full text-card-heading font-semibold"
        aria-live="polite"
      >
        {{ anchor.toFormat('LLLL yyyy') }}
      </h3>
      <button
        class="focus-ring calendar-button"
        aria-label="Previous month"
        @click="move(-1)"
      >
        Previous
      </button>
      <button
        class="focus-ring calendar-button"
        @click="goToday"
      >
        Today
      </button>
      <button
        class="focus-ring calendar-button"
        aria-label="Next month"
        @click="move(1)"
      >
        Next
      </button>
      <div
        class="flex gap-1 rounded-xl bg-surface-subtle p-1 sm:ml-auto"
        role="group"
        aria-label="Calendar view"
      >
        <button
          class="focus-ring calendar-button calendar-view"
          :aria-pressed="view === 'month'"
          @click="selectedView = 'month'"
        >
          Month
        </button>
        <button
          class="focus-ring calendar-button calendar-view"
          :aria-pressed="view === 'agenda'"
          @click="selectedView = 'agenda'"
        >
          Agenda
        </button>
      </div>
    </div>
    <div
      class="flex flex-wrap gap-1"
      role="group"
      aria-label="Calendar sources"
    >
      <button
        v-for="f in filters"
        :key="f.id"
        class="focus-ring calendar-button calendar-filter"
        :aria-pressed="filter === f.id"
        @click="filter = f.id"
      >
        {{ f.label }}
      </button>
    </div>
    <div
      v-if="calendar.isPending.value"
      role="status"
      aria-label="Loading calendar"
    >
      <SkeletonBlock height="320px" />
    </div>
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
        {{ filter === 'all' ? 'Nothing scheduled in this range. Dated Activities, Decision deadlines and payment schedules appear here.' : 'No matching items in this range.' }}
      </p>
      <table
        v-if="view === 'month'"
        class="w-full table-fixed border-collapse"
        aria-label="Month calendar"
      >
        <thead>
          <tr>
            <th
              v-for="day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']"
              :key="day"
              scope="col"
              class="py-2 text-meta font-medium text-muted"
            >
              {{ day }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(week, index) in weeks"
            :key="index"
          >
            <td
              v-for="day in week"
              :key="day.key"
              class="border border-line align-top p-0.5 sm:p-1 h-16 lg:h-36"
              :class="day.date.month !== anchor.month ? 'bg-surface-subtle text-muted' : ''"
            >
              <button
                class="focus-ring w-full min-h-11 rounded-lg text-sm text-center sm:text-left p-1"
                :class="day.key === today ? 'font-bold underline decoration-2 underline-offset-4 bg-brand-soft text-brand' : ''"
                :aria-label="`${day.date.toFormat('cccc, d LLLL yyyy')}, ${day.entries.length} entries`"
                :aria-current="day.key === today ? 'date' : undefined"
                :aria-pressed="selectedDay === day.key"
                @click="selectDay(day.key)"
              >
                {{ day.date.day }}<span
                  v-if="day.key === today"
                  class="sr-only"
                > Today</span>
                <span
                  v-if="compactMonth && day.entries.length"
                  class="block"
                >· {{ day.entries.length }}<span class="sr-only"> entries</span></span>
              </button>
              <div
                v-if="!compactMonth"
                class="space-y-1"
              >
                <CalendarEntryLink
                  v-for="entry in day.entries.slice(0, 2)"
                  :key="entry.entry_id"
                  :entry="entry"
                  :day="day.key"
                  :timezone="timezone"
                  compact
                />
                <button
                  v-if="day.entries.length > 2"
                  class="focus-ring min-h-11 rounded-lg text-meta text-brand underline"
                  :aria-label="`${day.entries.length - 2} more entries for ${day.date.toFormat('d LLLL')}`"
                  @click="selectDay(day.key)"
                >
                  +{{ day.entries.length - 2 }} more
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
      <div
        v-if="view === 'agenda' || selectedDay"
        class="space-y-6 max-w-3xl"
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
        >
          <h3 class="text-sm font-semibold mb-2">
            {{ day.date.toFormat('cccc, d LLLL yyyy') }}{{ day.key === today ? ' · Today' : '' }}
          </h3>
          <ul
            v-if="day.entries.length"
            class="rounded-xl border border-line bg-surface divide-y divide-line"
          >
            <li
              v-for="entry in day.entries"
              :key="entry.entry_id"
            >
              <CalendarEntryLink
                :entry="entry"
                :day="day.key"
                :timezone="timezone"
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
</template>

<style scoped>
.calendar-button { @apply min-h-11 rounded-lg border border-line bg-surface px-3 py-2 text-sm; }
.calendar-view { @apply border-transparent bg-transparent; }
.calendar-filter { @apply border-transparent bg-transparent text-ink-soft; }
.calendar-button[aria-pressed="true"] { @apply bg-brand-soft text-brand border-brand/20; }
</style>

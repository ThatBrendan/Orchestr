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
import AppIcon from '@/components/ui/AppIcon.vue';
import type { IconName } from '@/components/ui/icons';
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
const filters: { id: string; label: string; icon: IconName; tone: string }[] = [
  { id: 'all', label: 'All', icon: 'calendar', tone: 'text-ink-soft' },
  { id: 'activity', label: 'Activities', icon: 'checkCircle', tone: 'text-brand' },
  { id: 'decision', label: 'Decisions', icon: 'flag', tone: 'text-accent' },
  { id: 'payment_schedule', label: 'Payments', icon: 'coins', tone: 'text-warning' },
];
const entries = computed(() => (calendar.data.value ?? []).filter(e => filter.value === 'all' || e.source_type === filter.value || (filter.value === 'activity' && e.source_type === 'activity_occurrence')).sort((a, b) => entryDay(a, timezone.value).localeCompare(entryDay(b, timezone.value)) || (a.start_at ?? '').localeCompare(b.start_at ?? '') || a.entry_id.localeCompare(b.entry_id)));
const days = computed(() => Array.from({ length: Math.round(end.value.diff(start.value, 'days').days) }, (_, i) => {
  const date = start.value.plus({ days: i });
  const key = date.toISODate()!;
  return { key, date, entries: entries.value.filter(e => entryOnDay(e, key, timezone.value)) };
}));
const weeks = computed(() => Array.from({ length: days.value.length / 7 }, (_, i) => days.value.slice(i * 7, i * 7 + 7)));
const agenda = computed(() => days.value.filter(d => selectedDay.value ? d.key === selectedDay.value : d.entries.length));
const selected = computed(() => days.value.find(day => day.key === selectedDay.value));
// A small preview of the loaded range only; no new event projection or request.
const comingUp = computed(() => entries.value.filter(entry => entryDay(entry, timezone.value) >= today.value).slice(0, 3));
function move(delta: number) { month.value = anchor.value.plus({ months: delta }).toFormat('yyyy-MM'); selectedDay.value = null; }
function goToday() { month.value = today.value.slice(0, 7); selectedDay.value = null; }
function selectDay(day: string) { selectedDay.value = day; }
</script>

<template>
  <section
    class="space-y-5 min-w-0 fade-in"
    aria-label="Project execution calendar"
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h2 class="text-xl font-semibold">
          Calendar
        </h2>
        <p class="mt-1 text-sm text-ink-soft">
          Activities and deadlines, in one view.
        </p>
        <p class="mt-1 text-meta text-muted break-words">
          Times shown in {{ timezone }}
        </p>
      </div>
      <div class="flex flex-wrap gap-x-4 gap-y-1">
        <RouterLink
          class="min-h-11 inline-flex items-center text-sm text-brand focus-ring"
          :to="{ name: 'project.commitments', params: route.params }"
        >
          Go to Activities
        </RouterLink>
        <RouterLink
          :to="{ name: 'settings', hash: '#calendar-sync-settings' }"
          class="min-h-11 inline-flex items-center gap-2 rounded-lg text-sm text-ink-soft focus-ring"
        >
          <AppIcon
            name="settings"
            :size="16"
          />Calendar settings
        </RouterLink>
      </div>
    </header>
    <div
      class="flex flex-wrap gap-2"
      role="group"
      aria-label="Calendar sources"
    >
      <button
        v-for="f in filters"
        :key="f.id"
        class="focus-ring calendar-button calendar-filter inline-flex items-center gap-2"
        :aria-pressed="filter === f.id"
        @click="filter = f.id"
      >
        <AppIcon
          :name="f.icon"
          :size="16"
          :class="f.tone"
        />{{ f.label }}
      </button>
    </div>
    <div class="rounded-xl border border-line bg-surface p-3 sm:p-4 flex flex-wrap items-center gap-3">
      <div class="flex items-center gap-1">
        <button
          class="focus-ring calendar-button !px-3"
          aria-label="Previous month"
          @click="move(-1)"
        >
          <AppIcon
            name="chevronLeft"
            :size="18"
          />
        </button>
        <button
          class="focus-ring calendar-button !px-3"
          aria-label="Next month"
          @click="move(1)"
        >
          <AppIcon
            name="chevronRight"
            :size="18"
          />
        </button>
      </div>
      <h3
        class="text-base font-semibold"
        aria-live="polite"
      >
        {{ anchor.toFormat('LLLL yyyy') }}
      </h3>
      <button
        class="focus-ring calendar-button"
        @click="goToday"
      >
        Today
      </button>
      <div
        class="flex gap-1 rounded-lg bg-surface-subtle p-1 sm:ml-auto"
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
      v-if="calendar.isPending.value"
      role="status"
      aria-label="Loading calendar"
      class="calendar-layout"
    >
      <div
        v-if="view === 'month'"
        class="rounded-xl border border-line bg-surface p-3"
      >
        <div
          class="grid grid-cols-7 gap-2"
          aria-hidden="true"
        >
          <SkeletonBlock
            v-for="i in 7"
            :key="'heading'+i"
            height="24px"
          />
          <SkeletonBlock
            v-for="i in 35"
            :key="i"
            height="64px"
          />
        </div>
      </div>
      <div
        v-else
        class="space-y-3"
      >
        <SkeletonBlock
          v-for="i in 4"
          :key="i"
          height="96px"
          rounded="0.75rem"
        />
      </div>
      <div
        v-if="view === 'month'"
        class="rounded-xl border border-line bg-surface p-5 space-y-4"
      >
        <SkeletonBlock
          width="65%"
          height="24px"
        /><SkeletonBlock height="80px" /><SkeletonBlock height="80px" />
      </div>
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
      <div
        v-if="view === 'month'"
        class="calendar-layout"
      >
        <div class="min-w-0">
          <div class="rounded-xl border border-line bg-surface overflow-hidden">
            <table
              class="w-full table-fixed border-collapse"
              aria-label="Month calendar"
            >
              <thead>
                <tr>
                  <th
                    v-for="day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']"
                    :key="day"
                    scope="col"
                    class="py-3 text-xs font-medium text-muted bg-surface-subtle"
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
                    class="calendar-day border border-line align-top p-0.5 sm:p-1"
                    :class="[day.date.month !== anchor.month ? 'bg-surface-subtle/60 text-muted' : '', selectedDay === day.key ? 'selected-day' : '']"
                  >
                    <button
                      class="focus-ring w-full min-h-11 rounded-lg text-sm text-center p-1"
                      :class="selectedDay === day.key ? 'bg-brand text-white font-semibold' : day.key === today ? 'font-bold underline decoration-2 underline-offset-4 bg-brand-soft text-brand' : 'hover:bg-brand-soft'"
                      :aria-label="`${day.date.toFormat('cccc, d LLLL yyyy')}, ${day.entries.length} entries`"
                      :aria-description="!compactMonth && day.entries.length > 2 ? `${day.entries.length - 2} more entries. Select this date to see all entries.` : undefined"
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
                        class="block text-xs"
                      >· {{ day.entries.length }}<span class="sr-only"> entries</span></span>
                      <span
                        v-if="!compactMonth && day.entries.length > 2"
                        class="block text-xs font-medium"
                      >+{{ day.entries.length - 2 }} more</span>
                    </button>
                    <div
                      v-if="!compactMonth"
                      class="mt-1 space-y-1"
                    >
                      <CalendarEntryLink
                        v-for="entry in day.entries.slice(0, 2)"
                        :key="entry.entry_id"
                        :entry="entry"
                        :day="day.key"
                        :timezone="timezone"
                        compact
                      />
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
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
                :key="entry.entry_id"
              >
                <CalendarEntryLink
                  :entry="entry"
                  :day="selected.key"
                  :timezone="timezone"
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
                :key="entry.entry_id"
                class="p-3"
              >
                <p class="mb-2 text-meta font-medium text-ink-soft">
                  {{ DateTime.fromISO(entryDay(entry, timezone), { zone: timezone }).toFormat('ccc d LLL') }}
                </p>
                <CalendarEntryLink
                  :entry="entry"
                  :timezone="timezone"
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
.calendar-filter { @apply text-ink-soft; }
.calendar-button[aria-pressed="true"] { @apply bg-brand-soft text-brand border-brand/40; }
.calendar-view[aria-pressed="true"] { @apply bg-surface shadow-sm; }
.calendar-layout { display: grid; gap: 1.25rem; min-width: 0; }
.calendar-day { height: 5.5rem; }
.selected-day { box-shadow: inset 0 0 0 2px rgb(var(--brand)); background: rgb(var(--brand-soft)); }
@media (min-width: 1024px) { .calendar-day { height: 10rem; } }
@media (min-width: 1400px) { .calendar-layout { grid-template-columns: minmax(0, 1fr) 280px; align-items: start; } }
</style>

<script setup lang="ts" generic="T">
import type { DateTime } from 'luxon';
defineProps<{weeks: {key: string; date: DateTime; entries: T[]}[][]; anchorMonth: number; selectedDay: string | null; today: string; compactMonth: boolean; entryKey: (entry: T) => string; roomy?: boolean}>();
const emit = defineEmits<{select: [day: string]}>();
</script>
<template>
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
            :class="[day.date.month !== anchorMonth ? 'bg-surface-subtle/60 text-muted' : '', selectedDay === day.key ? 'selected-day' : '', roomy ? 'roomy-day' : '']"
          >
            <button
              class="focus-ring w-full min-h-11 rounded-lg text-sm text-center p-1"
              :class="selectedDay === day.key ? 'bg-brand text-white font-semibold' : day.key === today ? 'font-bold underline decoration-2 underline-offset-4 bg-brand-soft text-brand' : 'hover:bg-brand-soft'"
              :aria-label="`${day.date.toFormat('cccc, d LLLL yyyy')}, ${day.entries.length} entries`"
              :aria-description="!compactMonth && day.entries.length > 2 ? `${day.entries.length - 2} more entries. Select this date to see all entries.` : undefined"
              :aria-current="day.key === today ? 'date' : undefined"
              :aria-pressed="selectedDay === day.key"
              @click="emit('select', day.key)"
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
              <template
                v-for="entry in day.entries.slice(0, 2)"
                :key="entryKey(entry)"
              >
                <slot
                  name="entry"
                  :entry="entry"
                  :day="day.key"
                />
              </template>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
<style scoped>
.calendar-day { height: 5.5rem; }
.selected-day { box-shadow: inset 0 0 0 2px rgb(var(--brand)); background: rgb(var(--brand-soft)); }
@media (min-width: 1024px) { .calendar-day { height: 10rem; } .roomy-day { height: 12rem; } }
</style>

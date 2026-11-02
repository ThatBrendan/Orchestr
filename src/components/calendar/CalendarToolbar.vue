<script setup lang="ts">
import AppIcon from '@/components/ui/AppIcon.vue';
withDefaults(defineProps<{label: string; view: 'month' | 'agenda'; headingLevel?: 2 | 3}>(), { headingLevel: 3 });
const emit = defineEmits<{previous: []; next: []; today: []; 'update:view': [view: 'month' | 'agenda']}>();
</script>
<template>
  <div class="rounded-xl border border-line bg-surface p-3 sm:p-4 flex flex-wrap items-center gap-3">
    <div class="flex items-center gap-1">
      <button
        class="focus-ring calendar-button !px-3"
        aria-label="Previous month"
        @click="emit('previous')"
      >
        <AppIcon
          name="chevronLeft"
          :size="18"
        />
      </button>
      <button
        class="focus-ring calendar-button !px-3"
        aria-label="Next month"
        @click="emit('next')"
      >
        <AppIcon
          name="chevronRight"
          :size="18"
        />
      </button>
    </div>
    <component
      :is="headingLevel === 2 ? 'h2' : 'h3'"
      class="text-base font-semibold"
      aria-live="polite"
    >
      {{ label }}
    </component>
    <button
      class="focus-ring calendar-button"
      @click="emit('today')"
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
        @click="emit('update:view', 'month')"
      >
        Month
      </button>
      <button
        class="focus-ring calendar-button calendar-view"
        :aria-pressed="view === 'agenda'"
        @click="emit('update:view', 'agenda')"
      >
        Agenda
      </button>
    </div>
  </div>
</template>
<style scoped>
.calendar-button { @apply min-h-11 rounded-lg border border-line bg-surface px-3 py-2 text-sm; }
.calendar-view { @apply border-transparent bg-transparent; }
.calendar-view[aria-pressed="true"] { @apply bg-surface text-brand border-brand/40 shadow-sm; }
</style>

<script setup lang="ts">
import SkeletonBlock from '@/components/ui/SkeletonBlock.vue';
defineProps<{view: 'month' | 'agenda'}>();
</script>
<template>
  <div
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
</template>
<style scoped>
.calendar-layout { display: grid; gap: 1.25rem; min-width: 0; }
@media (min-width: 1400px) { .calendar-layout { grid-template-columns: minmax(0, 1fr) 280px; align-items: start; } }
</style>

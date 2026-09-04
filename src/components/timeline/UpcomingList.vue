<script setup lang="ts">
import { computed } from "vue";
import type { TimelineEvent } from "@/types/derived";
import { useProjectTime } from "@/composables/useProjectTime";

const props = defineProps<{ events: TimelineEvent[]; timezone: string }>();
const t = computed(() => useProjectTime(props.timezone));

interface Group {
  day: string;
  items: { label: string; time: string; allDay: boolean }[];
}

const groups = computed<Group[]>(() => {
  const byDay = new Map<string, Group>();
  for (const e of props.events) {
    const day = t.value.dayLabel(e.occurs_at);
    if (!byDay.has(day)) byDay.set(day, { day, items: [] });
    byDay.get(day)!.items.push({
      label: e.title,
      time: e.all_day ? "" : t.value.time(e.occurs_at),
      allDay: e.all_day,
    });
  }
  return [...byDay.values()];
});
</script>

<template>
  <div class="mt-3 border rounded-xl divide-y border-line bg-surface">
    <div v-for="g in groups" :key="g.day" class="px-4 py-3.5">
      <div class="text-[12.5px] font-medium mb-2 text-muted">{{ g.day }}</div>
      <div class="space-y-2">
        <div v-for="(i, idx) in g.items" :key="idx" class="flex items-center gap-3 text-14">
          <span class="tnum w-12 shrink-0 text-ink-soft">{{ i.allDay ? "All day" : i.time }}</span>
          <span>{{ i.label }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

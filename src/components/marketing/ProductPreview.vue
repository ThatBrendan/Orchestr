<script setup lang="ts">
/**
 * Static marketing visual — a composed, illustrative snapshot of the Orchestrio
 * product surface. NO network calls, NO composables, NO live data. The sample
 * content below is fixed marketing copy, scoped to this component.
 */
import StatTile from "@/components/ui/StatTile.vue";
import ProgressBar from "@/components/ui/ProgressBar.vue";
import SeverityIcon from "@/components/ui/SeverityIcon.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import { presentLabel } from "@/lib/presentation";

const SAMPLE = {
  name: "Team offsite — Lisbon",
  dates: "12–15 March",
  progress: 68,
  tiles: [
    { value: "£9,000", label: "Total budget" },
    { value: "£7,240", label: "Committed" },
    { value: "£1,760", label: "Remaining" },
    { value: "68%", label: "Complete" },
  ],
  findings: [
    { severity: "blocker" as const, text: "£1,200 venue balance overdue" },
    { severity: "warning" as const, text: "Airport transfer has no owner" },
    { severity: "warning" as const, text: "Dinner booking has no reference" },
  ],
  commitments: [
    { title: "Venue hire", owner: "Priya", status: "Booked", tone: "accent" as const },
    { title: "Flights", owner: "Sam", status: "Confirmed", tone: "accent" as const },
    { title: "Airport transfer", owner: "Unassigned", status: "Researching", tone: "amber" as const },
  ],
};
</script>

<template>
  <div
    class="rounded-2xl border border-line bg-surface shadow-[0_1px_2px_rgba(20,20,18,0.04),0_12px_32px_-12px_rgba(20,20,18,0.12)] overflow-hidden"
    role="img"
    aria-label="Illustration of the Orchestrio project workspace: budget summary, commitments with owners, and planning health findings"
  >
    <!-- header -->
    <div class="px-5 pt-5">
      <div class="flex items-start justify-between gap-4">
        <div>
          <div class="font-medium text-[15px]">
            {{ SAMPLE.name }}
          </div>
          <div class="text-13 text-muted mt-0.5">
            {{ SAMPLE.dates }}
          </div>
        </div>
        <div class="text-13 font-medium text-amber shrink-0">
          3 need attention
        </div>
      </div>
      <div class="mt-3">
        <ProgressBar :value="SAMPLE.progress" />
      </div>
    </div>

    <!-- tiles -->
    <div class="mt-5 px-5 py-4 border-y border-line flex flex-wrap gap-x-8 gap-y-3 bg-[#FCFCFB]">
      <StatTile
        v-for="t in SAMPLE.tiles"
        :key="t.label"
        :value="t.value"
        :label="t.label"
      />
    </div>

    <div class="grid sm:grid-cols-2">
      <!-- commitments -->
      <div class="p-5 sm:border-r border-line">
        <div class="text-[11px] font-semibold uppercase tracking-wide text-muted">
          Commitments
        </div>
        <div class="mt-2.5 space-y-2.5">
          <div
            v-for="c in SAMPLE.commitments"
            :key="c.title"
            class="flex items-center gap-3"
          >
            <div class="min-w-0 flex-1">
              <div class="text-14 font-medium truncate">
                {{ c.title }}
              </div>
              <div
                class="text-13"
                :class="c.owner === 'Unassigned' ? 'text-amber' : 'text-ink-soft'"
              >
                {{ c.owner }}
              </div>
            </div>
            <StatusBadge
              :label="presentLabel(c.status)"
              :tone="c.tone"
            />
          </div>
        </div>
      </div>

      <!-- health -->
      <div class="p-5 border-t sm:border-t-0 border-line">
        <div class="text-[11px] font-semibold uppercase tracking-wide text-muted">
          Planning health
        </div>
        <div class="mt-2.5 space-y-2.5">
          <div
            v-for="(f, i) in SAMPLE.findings"
            :key="i"
            class="flex items-center gap-3"
          >
            <SeverityIcon :severity="f.severity" />
            <span class="text-13.5 text-ink-soft">{{ f.text }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { budgetVisual } from "@/lib/budgetVisual";
import { useMoney } from "@/composables/useMoney";
const props = defineProps<{ target: number | null; planned: number; paid: number; currency: string }>();
const { format } = useMoney();
const visual = computed(() => budgetVisual(props.target, props.planned, props.paid));
</script>
<template>
  <figure class="rounded-xl border border-line bg-surface p-5 space-y-4">
    <figcaption class="text-14 font-medium">
      Planning and payments
    </figcaption>
    <div>
      <p class="text-13 mb-2">
        Planned spend · {{ format(planned, currency) }}
      </p>
      <div
        class="flex h-5 rounded overflow-hidden bg-line"
        aria-hidden="true"
      >
        <span
          class="bg-accent"
          :style="{ width: visual.plannedWidth + '%' }"
        />
        <span
          class="bg-amber"
          :style="{ width: visual.overWidth + '%' }"
        />
      </div>
    </div>
    <div>
      <p class="text-13 mb-2">
        Paid so far · {{ format(paid, currency) }}
      </p>
      <div
        class="h-3 rounded overflow-hidden bg-line"
        aria-hidden="true"
      >
        <div
          class="h-full bg-ink-soft"
          :style="{ width: visual.paidWidth + '%' }"
        />
      </div>
    </div>
    <div class="flex flex-wrap gap-x-5 gap-y-2 text-13">
      <span>{{ target == null ? 'Planned' : 'Planned within target' }}: {{ format(visual.within, currency) }}</span>
      <span v-if="target != null">Over budget: {{ format(visual.over, currency) }}</span>
      <span>Target: {{ target == null ? 'Not set' : format(target, currency) }}</span>
    </div>
    <p class="text-13 text-muted">
      Both bars use the same scale. Paid is net of refunds and includes cancelled Activity payment history; it is separate from planned spend.<span v-if="paid < 0"> Net refunds exceed outgoing payments; the payment bar shows their magnitude.</span>
    </p>
  </figure>
</template>

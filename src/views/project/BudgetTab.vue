<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useProjectFinancials, useBudgetCategoryActuals } from "@/composables/useProject";
import { useProjectContext } from "@/composables/useProjectContext";
import { useMoney } from "@/composables/useMoney";
import { categoryLabel } from "@/lib/commitmentCategories";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import StatTile from "@/components/ui/StatTile.vue";
import SectionHeading from "@/components/ui/SectionHeading.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project } = useProjectContext();
const currency = computed(() => project.value?.currency ?? "GBP");

const { financials, isPending, isError, error, refetch } = useProjectFinancials(projectId);
const { categories, isPending: catPending } = useBudgetCategoryActuals(projectId);
const { format } = useMoney();

const hasTarget = computed(() => financials.value?.total_target_minor != null);

function varianceLabel(minor: number | null | undefined): string {
  if (minor == null) return "—";
  if (minor < 0) return `${format(Math.abs(minor), currency.value)} over`;
  return `${format(minor, currency.value)} under`;
}

const categoriesWithData = computed(() => categories.value.filter((c) => c.target_minor != null || c.actual_minor > 0));

</script>

<template>
  <div class="fade-in">
    <div v-if="isPending" class="grid sm:grid-cols-3 gap-4">
      <SkeletonBlock v-for="i in 6" :key="i" height="52px" rounded="0.5rem" />
    </div>
    <ErrorState v-else-if="isError" :error="error" :retry="() => refetch()" />
    <template v-else-if="financials">
      <div class="border rounded-xl px-6 py-5 border-line bg-surface grid sm:grid-cols-3 gap-x-8 gap-y-5">
        <StatTile :value="hasTarget ? format(financials.total_target_minor, currency) : 'Not set'" label="Total budget" />
        <StatTile :value="format(financials.committed_spend_minor, currency)" label="Committed spend" />
        <StatTile :value="format(financials.net_actual_spend_minor, currency)" label="Paid amount" />
        <StatTile :value="format(financials.outstanding_minor, currency)" label="Outstanding" />
        <StatTile
          :value="hasTarget ? format(financials.remaining_budget_minor, currency) : '—'"
          label="Remaining budget"
          :tone="hasTarget && (financials.remaining_budget_minor ?? 0) < 0 ? 'amber' : 'default'"
        />
        <StatTile :value="(financials.progress_pct ?? 0) + '%'" label="Complete" />
      </div>

      <div v-if="hasTarget" class="mt-5 border rounded-xl px-6 py-4 border-line bg-surface grid sm:grid-cols-2 gap-4">
        <div>
          <div class="text-13 text-muted">Projected variance</div>
          <div class="text-14 font-medium mt-0.5" :class="(financials.projected_variance_minor ?? 0) < 0 ? 'text-amber' : 'text-ink'">
            {{ varianceLabel(financials.projected_variance_minor) }}
          </div>
          <div class="text-13 text-muted mt-0.5">Target vs. committed spend (open activities included)</div>
        </div>
        <div>
          <div class="text-13 text-muted">Settled variance</div>
          <div class="text-14 font-medium mt-0.5" :class="(financials.settled_variance_minor ?? 0) < 0 ? 'text-amber' : 'text-ink'">
            {{ varianceLabel(financials.settled_variance_minor) }}
          </div>
          <div class="text-13 text-muted mt-0.5">Target vs. money actually paid so far</div>
        </div>
      </div>
      <p v-else class="mt-4 text-13 text-muted">No total budget has been set. Budget target editing is not available in this build.</p>

      <div class="mt-8">
        <SectionHeading label="By category" />
        <div v-if="catPending" class="mt-3 space-y-2">
          <SkeletonBlock v-for="i in 3" :key="i" height="44px" rounded="0.5rem" />
        </div>
        <EmptyState v-else-if="categoriesWithData.length === 0" class="mt-3" message="No spend or category targets recorded yet." />
        <div v-else class="mt-3 border rounded-xl divide-y border-line bg-surface">
          <div v-for="c in categoriesWithData" :key="c.kind" class="flex items-center gap-4 px-4 py-3">
            <span class="text-14 flex-1">{{ categoryLabel(c.kind) }}</span>
            <span class="text-13.5 text-muted w-32 text-right">{{ format(c.actual_minor, currency) }} actual</span>
            <span class="text-13.5 text-muted w-32 text-right">{{ c.target_minor != null ? format(c.target_minor, currency) + " target" : "no target" }}</span>
            <span
              v-if="c.variance_minor != null"
              class="text-13.5 font-medium w-28 text-right"
              :class="c.variance_minor < 0 ? 'text-amber' : 'text-ink-soft'"
            >
              {{ varianceLabel(c.variance_minor) }}
            </span>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

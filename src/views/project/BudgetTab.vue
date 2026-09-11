<script setup lang="ts">
import MemberBalances from "@/components/budget/MemberBalances.vue";
import BudgetVisual from "@/components/budget/BudgetVisual.vue";
import BudgetTargetDialog from "@/components/budget/BudgetTargetDialog.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { computed, ref } from "vue";
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
const { project, allowed } = useProjectContext();
const currency = computed(() => project.value?.currency ?? "GBP");

const { financials, isPending, isError, error, refetch } = useProjectFinancials(projectId);
const { categories, isPending: catPending, isError: catFailed, error: catError, refetch: refetchCategories } = useBudgetCategoryActuals(projectId);
const { format } = useMoney();

const budgetOpen = ref(false);
const canEditBudget = computed(() => allowed("budget.edit") && project.value?.status !== "archived");
const hasTarget = computed(() => financials.value?.total_target_minor != null);

function varianceLabel(minor: number | null | undefined): string {
  if (minor == null) return "—";
  if (minor === 0) return "On budget";
  if (minor < 0) return `${format(Math.abs(minor), currency.value)} over`;
  return `${format(minor, currency.value)} under`;
}

const categoriesWithData = computed(() => categories.value.filter((c) => c.target_minor != null || c.actual_minor > 0 || c.net_paid_minor !== 0));

</script>

<template>
  <div class="fade-in">
    <div
      v-if="isPending"
      class="grid sm:grid-cols-3 gap-4"
    >
      <SkeletonBlock
        v-for="i in 6"
        :key="i"
        height="52px"
        rounded="0.5rem"
      />
    </div>
    <ErrorState
      v-else-if="isError"
      :error="error"
      :retry="() => refetch()"
    />
    <template v-else-if="financials">
      <div class="mb-4 flex justify-end">
        <AppButton
          v-if="canEditBudget"
          size="sm"
          @click="budgetOpen = true"
        >
          {{ hasTarget ? 'Edit budget' : 'Set budget' }}
        </AppButton>
      </div>
      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <div class="border border-line rounded-xl bg-surface p-5">
          <StatTile
            :value="hasTarget ? format(financials.total_target_minor, currency) : 'Not set'"
            label="Total budget"
          />
        </div>
        <div class="border border-line rounded-xl bg-surface p-5">
          <StatTile
            :value="format(financials.total_cost_minor, currency)"
            label="Planned spend"
          />
        </div>
        <div class="border border-line rounded-xl bg-surface p-5">
          <StatTile
            :value="format(financials.net_actual_spend_minor, currency)"
            label="Paid so far"
          />
        </div>
        <div class="border border-line rounded-xl bg-surface p-5">
          <StatTile
            :value="hasTarget ? format(Math.abs(financials.remaining_budget_minor ?? 0), currency) : '—'"
            :label="(financials.remaining_budget_minor ?? 0) < 0 ? 'Over budget' : 'Remaining budget'"
            :tone="(financials.remaining_budget_minor ?? 0) < 0 ? 'amber' : 'default'"
          />
        </div>
      </div>
      <p
        v-if="!hasTarget"
        class="my-4 text-13 text-muted"
      >
        Set an approximate project budget to track spending against a target.
      </p>
      <BudgetVisual
        class="mt-5"
        :target="financials.total_target_minor"
        :planned="financials.total_cost_minor"
        :paid="financials.net_actual_spend_minor"
        :currency="currency"
      />
      <div class="grid md:grid-cols-2 gap-5 mt-5">
        <section class="rounded-xl border border-line p-5 bg-surface">
          <h2 class="font-medium mb-4">
            Planning
          </h2>
          <dl class="space-y-3 text-14">
            <div class="flex flex-wrap justify-between gap-2">
              <dt>Budget target</dt><dd>{{ hasTarget ? format(financials.total_target_minor, currency) : 'Not set' }}</dd>
            </div>
            <div class="flex flex-wrap justify-between gap-2">
              <dt>Planned spend</dt><dd>{{ format(financials.total_cost_minor, currency) }}</dd>
            </div>
            <div class="flex flex-wrap justify-between gap-2">
              <dt>{{ (financials.remaining_budget_minor ?? 0) < 0 ? 'Over budget' : 'Remaining budget' }}</dt><dd>{{ hasTarget ? format(Math.abs(financials.remaining_budget_minor ?? 0), currency) : '—' }}</dd>
            </div>
            <div class="flex flex-wrap justify-between gap-2">
              <dt>Budget used</dt><dd>{{ financials.budget_used_pct == null ? '—' : financials.budget_used_pct + '%' }}</dd>
            </div>
            <div class="flex flex-wrap justify-between gap-2">
              <dt>Projected variance</dt><dd>{{ varianceLabel(financials.projected_variance_minor) }}</dd>
            </div>
          </dl>
          <p class="mt-4 text-13 text-muted">
            Planned spend includes all noncancelled Activities, using final cost when known, otherwise agreed price or estimate.
          </p>
        </section>
        <section class="rounded-xl border border-line p-5 bg-surface">
          <h2 class="font-medium mb-4">
            Payments
          </h2>
          <dl class="space-y-3 text-14">
            <div class="flex flex-wrap justify-between gap-2">
              <dt>Paid so far</dt><dd>{{ format(financials.net_actual_spend_minor, currency) }}</dd>
            </div>
            <div class="flex flex-wrap justify-between gap-2">
              <dt>Outstanding payments</dt><dd>{{ format(financials.outstanding_minor, currency) }}</dd>
            </div>
            <div class="flex flex-wrap justify-between gap-2">
              <dt>Paid variance</dt><dd>{{ varianceLabel(financials.settled_variance_minor) }}</dd>
            </div>
          </dl>
          <p class="mt-4 text-13 text-muted">
            Paid so far is net of refunds. Outstanding covers unpaid costs of confirmed, booked and completed Activities. Paid variance compares payments with the budget target.
          </p>
        </section>
      </div>
      <section class="mt-8">
        <SectionHeading label="By category" />
        <SkeletonBlock
          v-if="catPending"
          class="mt-3"
          height="80px"
        />
        <ErrorState
          v-else-if="catFailed"
          :error="catError"
          :retry="() => refetchCategories()"
        />
        <EmptyState
          v-else-if="categoriesWithData.length === 0"
          class="mt-3"
          message="No planned spending yet. Add estimated costs to Activities to see a category breakdown."
        />
        <div
          v-else
          class="mt-3 overflow-x-auto border border-line rounded-xl"
          role="region"
          aria-label="Budget by category"
          tabindex="0"
        >
          <table class="w-full text-14 whitespace-nowrap">
            <caption class="sr-only">
              Category targets, planned costs and payment settlement
            </caption>
            <thead class="bg-surface text-muted">
              <tr>
                <th
                  v-for="heading in ['Category', 'Target', 'Planned', 'Paid', 'Variance', 'Status']"
                  :key="heading"
                  scope="col"
                  class="px-4 py-3 text-left"
                >
                  {{ heading }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-line">
              <tr
                v-for="c in categoriesWithData"
                :key="c.kind"
              >
                <th
                  scope="row"
                  class="px-4 py-3 text-left font-medium"
                >
                  {{ categoryLabel(c.kind) }}
                </th>
                <td class="px-4 py-3 text-right">
                  {{ c.target_minor == null ? '—' : format(c.target_minor, currency) }}
                </td>
                <td class="px-4 py-3 text-right">
                  {{ format(c.actual_minor, currency) }}
                </td>
                <td class="px-4 py-3 text-right">
                  {{ format(c.net_paid_minor, currency) }}
                </td>
                <td class="px-4 py-3 text-right">
                  {{ varianceLabel(c.variance_minor) }}
                </td>
                <td
                  class="px-4 py-3"
                  :class="c.variance_minor != null && c.variance_minor < 0 ? 'text-amber' : 'text-muted'"
                >
                  {{ c.variance_minor == null ? 'No target' : c.variance_minor < 0 ? 'Over budget' : c.variance_minor === 0 ? 'On budget' : 'On track' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      <MemberBalances
        :project-id="projectId"
        :currency="currency"
      />
      <BudgetTargetDialog
        :open="budgetOpen"
        :project-id="projectId"
        :currency="currency"
        :target="financials.total_target_minor"
        @close="budgetOpen = false"
      />
    </template>
  </div>
</template>

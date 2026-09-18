<script setup lang="ts">
import MemberBalances from "@/components/budget/MemberBalances.vue";
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
      <div class="grid gap-4 sm:grid-cols-3">
        <div class="border border-line rounded-xl bg-surface p-5">
          <StatTile
            :value="hasTarget ? format(financials.total_target_minor, currency) : 'Not set'"
            label="Total budget"
          />
        </div>
        <div class="border border-line rounded-xl bg-surface p-5">
          <StatTile
            :value="format(financials.net_actual_spend_minor, currency)"
            label="Spent so far"
          />
        </div>

        <div class="border border-line rounded-xl bg-surface p-5">
          <StatTile
            :value="hasTarget ? format(Math.abs(financials.settled_variance_minor ?? 0), currency) : '—'"
            :label="(financials.settled_variance_minor ?? 0) < 0 ? 'Over budget' : 'Remaining budget'"
            :tone="(financials.settled_variance_minor ?? 0) < 0 ? 'amber' : 'default'"
          />
        </div>
      </div>
      <p
        v-if="!hasTarget"
        class="my-4 text-13 text-muted"
      >
        Set an approximate project budget to track spending against a target.
      </p>
      <MemberBalances
        :project-id="projectId"
        :currency="currency"
      />
    
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
          message="No spending recorded yet. Add costs to Activities to see a category breakdown."
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
              Category targets and recorded expenses
            </caption>
            <thead class="bg-surface text-muted">
              <tr>
                <th
                  v-for="heading in ['Category', 'Target', 'Spent so far']"
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
                  {{ format(c.net_paid_minor, currency) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      
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

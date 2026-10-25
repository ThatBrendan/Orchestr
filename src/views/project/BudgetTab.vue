<script setup lang="ts">
import { useExecutionDialogFocus } from "@/composables/useExecutionDialogFocus";
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

const focusFallback = ref<HTMLElement | null>(null);
const restoreDialogFocus = useExecutionDialogFocus(budgetOpen, focusFallback);
</script>

<template>
  <div class="space-y-6 max-w-4xl fade-in">
    <h2
      ref="focusFallback"
      tabindex="-1"
      class="text-section-heading focus-ring"
    >
      Budget
    </h2>
    <div
      v-if="isPending"
      role="status"
      aria-label="Loading budget"
    >
      <SkeletonBlock
        height="180px"
        rounded="0.75rem"
      />
    </div>
    <ErrorState
      v-else-if="isError"
      :error="error"
      :retry="() => refetch()"
    />
    <section
      v-else-if="financials"
      class="rounded-xl border border-line bg-surface p-4 sm:p-5"
      aria-label="Project financial summary"
    >
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="text-sm text-ink-soft">
            Spent so far
          </p><p class="mt-1 text-page-title tnum [overflow-wrap:anywhere]">
            {{ format(financials.net_actual_spend_minor, currency) }}
          </p>
        </div>
        <AppButton
          v-if="canEditBudget"
          variant="secondary"
          @click="budgetOpen = true"
        >
          {{ hasTarget ? 'Edit budget' : 'Set budget' }}
        </AppButton>
      </div>
      <dl class="mt-5 grid gap-4 sm:grid-cols-2 border-t border-line pt-4">
        <div>
          <dt class="text-meta text-muted">
            Total budget
          </dt><dd class="mt-1 text-card-heading tnum [overflow-wrap:anywhere]">
            {{ hasTarget ? format(financials.total_target_minor, currency) : 'Not set' }}
          </dd>
        </div>
        <div>
          <dt class="text-meta text-muted">
            {{ (financials.settled_variance_minor ?? 0) < 0 ? 'Over budget' : 'Remaining budget' }}
          </dt><dd
            class="mt-1 text-card-heading tnum [overflow-wrap:anywhere]"
            :class="(financials.settled_variance_minor ?? 0) < 0 ? 'text-warning' : ''"
          >
            {{ hasTarget ? format(Math.abs(financials.settled_variance_minor ?? 0), currency) : '—' }}
          </dd>
        </div>
      </dl>
      <p
        v-if="!hasTarget"
        class="mt-4 text-meta text-muted"
      >
        Set an approximate budget to track spending against a target.
      </p>
    </section>
    <MemberBalances
      :project-id="projectId"
      :currency="currency"
    />
    <section
      class="border-t border-line pt-6 space-y-3"
      aria-label="Category budgets"
    >
      <h2 class="text-section-heading">
        By category
      </h2>
      <SkeletonBlock
        v-if="catPending"
        height="100px"
      />
      <ErrorState
        v-else-if="catFailed"
        :error="catError"
        :retry="() => refetchCategories()"
      />
      <EmptyState
        v-else-if="categoriesWithData.length === 0"
        message="No category targets or spending yet. Activity costs appear here by category."
      />
      <div
        v-else
        class="rounded-xl border border-line bg-surface divide-y divide-line"
      >
        <article
          v-for="c in categoriesWithData"
          :key="c.kind"
          class="p-4 sm:flex sm:items-center sm:justify-between gap-4"
        >
          <h3 class="text-card-heading font-medium [overflow-wrap:anywhere]">
            {{ categoryLabel(c.kind) }}
          </h3>
          <dl class="mt-3 sm:mt-0 grid grid-cols-2 gap-4 sm:min-w-64">
            <div>
              <dt class="text-meta text-muted">
                Target
              </dt><dd class="mt-1 text-sm tnum [overflow-wrap:anywhere]">
                {{ c.target_minor == null ? 'Not set' : format(c.target_minor, currency) }}
              </dd>
            </div>
            <div>
              <dt class="text-meta text-muted">
                Spent so far
              </dt><dd class="mt-1 text-sm tnum [overflow-wrap:anywhere]">
                {{ format(c.net_paid_minor, currency) }}
              </dd>
            </div>
          </dl>
        </article>
      </div>
    </section>
    <BudgetTargetDialog
      v-if="financials"
      :open="budgetOpen"
      :project-id="projectId"
      :currency="currency"
      :target="financials.total_target_minor"
      @after-close="restoreDialogFocus"
      @close="budgetOpen = false"
    />
  </div>
</template>

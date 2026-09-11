<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProjectHealth, useProjectOverview, useUpcoming } from "@/composables/useProject";
import { useMoney } from "@/composables/useMoney";
import { isProjectModuleVisible } from "@/lib/projectProfiles";
import { overviewConfig, type OverviewCardKey } from "@/lib/projectOverview";
import SectionHeading from "@/components/ui/SectionHeading.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import AttentionRow from "@/components/health/AttentionRow.vue";
import UpcomingList from "@/components/timeline/UpcomingList.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project } = useProjectContext();
const { format } = useMoney();

const projectOverview = useProjectOverview(projectId);
const health = useProjectHealth(projectId);
const upcoming = useUpcoming(projectId);
const overview = computed(() => projectOverview.overview.value);
const currency = computed(() => project.value?.currency ?? "GBP");
const budgetVisible = computed(() =>
  isProjectModuleVisible(project.value?.profile, project.value?.module_visibility, "budget"),
);
const cardOrder = computed(() =>
  overviewConfig(project.value?.profile).cards.filter((card) => card !== "budget" || budgetVisible.value),
);

function countLabel(count: number | null | undefined, singular: string, plural = `${singular}s`): string {
  const value = count ?? 0;
  return `${value} ${value === 1 ? singular : plural}`;
}

function humanizeStatus(value: string | null | undefined): string {
  return (value ?? "healthy").replace(/_/g, " ");
}

function countdownValue(): string {
  if (!overview.value) return "—";
  if (overview.value.days_until_end != null) {
    if (overview.value.days_until_end < 0) return "Ended";
    if (overview.value.days_until_end === 0) return "Today";
    return `${overview.value.days_until_end}d`;
  }
  if (overview.value.days_until_start != null) {
    if (overview.value.days_until_start < 0) return "Started";
    if (overview.value.days_until_start === 0) return "Today";
    return `${overview.value.days_until_start}d`;
  }
  return "No date";
}

function cardModel(card: OverviewCardKey) {
  const o = overview.value;
  if (!o) return null;
  const models = {
    countdown: {
      label: "Countdown",
      value: countdownValue(),
      detail: o.ends_on ? "Until project end" : o.starts_on ? "Until project start" : "Add project dates",
      tone: "default",
    },
    progress: {
      label: "Progress",
      value: `${o.progress_pct ?? 0}%`,
      detail: `${countLabel(o.completed_activity_count, "completed")} · ${countLabel(o.open_activity_count, "open")}`,
      tone: "default",
    },
    activities: {
      label: "Activities",
      value: String(o.activity_count),
      detail: `${countLabel(o.task_count, "task")} · ${countLabel(o.purchase_count, "purchase")}`,
      tone: "default",
    },
    bookings: {
      label: "Bookings",
      value: `${o.booked_booking_count}/${o.booking_count}`,
      detail: `${countLabel(o.supplier_count, "supplier")} tracked`,
      tone: "default",
    },
    budget: {
      label: "Budget",
      value: format(o.total_target_minor, currency.value),
      detail: o.remaining_budget_minor == null ? "No budget target set" : `${format(o.remaining_budget_minor, currency.value)} remaining`,
      tone: o.remaining_budget_minor != null && o.remaining_budget_minor < 0 ? "amber" : "default",
    },
    payments: {
      label: "Payments",
      value: format(o.outstanding_minor, currency.value),
      detail: `${countLabel(o.payment_overdue_count, "overdue")} · ${countLabel(o.payment_due_soon_count, "due soon", "due soon")}`,
      tone: o.payment_overdue_count > 0 ? "amber" : "default",
    },
    people: {
      label: "People",
      value: String(o.active_member_count),
      detail: "Active collaborators",
      tone: "default",
    },
    milestones: {
      label: "Milestones",
      value: String(o.upcoming_milestone_count),
      detail: o.next_milestone_on ? `Next ${o.next_milestone_on}` : `${countLabel(o.milestone_count, "milestone")} total`,
      tone: "default",
    },
    overdue: {
      label: "Overdue",
      value: String(o.overdue_activity_count),
      detail: "Activities past their date",
      tone: o.overdue_activity_count > 0 ? "amber" : "default",
    },
    owners: {
      label: "Owners",
      value: String(o.unowned_activity_count),
      detail: "Open activities without an owner",
      tone: o.unowned_activity_count > 0 ? "amber" : "default",
    },
    health: {
      label: "Planning Health",
      value: String(o.attention_count ?? 0),
      detail: humanizeStatus(o.health_status),
      tone: (o.attention_count ?? 0) > 0 ? "amber" : "default",
    },
    upcoming: {
      label: "Upcoming",
      value: String(upcoming.events.value.length),
      detail: "Next 14 days",
      tone: "default",
    },
  } satisfies Record<OverviewCardKey, { label: string; value: string; detail: string; tone: "default" | "amber" }>;
  return models[card];
}
</script>

<template>
  <div class="fade-in space-y-8">
    <div>
      <SectionHeading label="Overview" />
      <div
        v-if="projectOverview.isPending.value"
        class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
      >
        <SkeletonBlock
          v-for="i in 6"
          :key="i"
          height="104px"
          rounded="0.75rem"
        />
      </div>
      <ErrorState
        v-else-if="projectOverview.isError.value"
        class="mt-3"
        :error="projectOverview.error.value"
        :retry="() => projectOverview.refetch()"
      />
      <div
        v-else
        class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
      >
        <div
          v-for="card in cardOrder"
          :key="card"
          class="rounded-xl border border-line bg-surface p-4"
        >
          <template v-if="cardModel(card)">
            <div class="flex items-start justify-between gap-2">
              <p class="text-13 font-medium text-muted">
                {{ cardModel(card)?.label }}
              </p>
              <StatusBadge
                v-if="card === 'health' && overview?.health_status"
                :label="humanizeStatus(overview.health_status)"
                :tone="(overview.attention_count ?? 0) > 0 ? 'amber' : 'accent'"
              />
            </div>
            <div
              class="mt-2 font-display text-[24px] font-semibold tnum"
              :class="cardModel(card)?.tone === 'amber' ? 'text-amber' : 'text-ink'"
            >
              {{ cardModel(card)?.value }}
            </div>
            <p class="mt-1 text-13 text-ink-soft">
              {{ cardModel(card)?.detail }}
            </p>
          </template>
        </div>
      </div>
    </div>

    <div class="grid md:grid-cols-2 gap-8">
      <!-- Needs attention -->
      <div>
        <SectionHeading label="Needs attention" />
        <div
          v-if="health.isPending.value"
          class="mt-3 space-y-2"
        >
          <SkeletonBlock
            v-for="i in 3"
            :key="i"
            height="56px"
            rounded="0.5rem"
          />
        </div>
        <ErrorState
          v-else-if="health.isError.value"
          class="mt-3"
          :error="health.error.value"
          :retry="() => health.refetch()"
        />
        <EmptyState
          v-else-if="health.needsAttention.value.length === 0"
          class="mt-3"
          message="All clear — nothing needs attention on this project."
        />
        <div
          v-else
          class="mt-3 border rounded-xl divide-y border-line bg-surface"
        >
          <AttentionRow
            v-for="(f, i) in health.needsAttention.value"
            :key="f.code + (f.subject_id ?? '') + i"
            :finding="f"
          />
        </div>
      </div>

      <!-- Upcoming -->
      <div>
        <SectionHeading label="Upcoming" />
        <div
          v-if="upcoming.isPending.value"
          class="mt-3 space-y-2"
        >
          <SkeletonBlock
            v-for="i in 2"
            :key="i"
            height="72px"
            rounded="0.5rem"
          />
        </div>
        <ErrorState
          v-else-if="upcoming.isError.value"
          class="mt-3"
          :error="upcoming.error.value"
          :retry="() => upcoming.refetch()"
        />
        <EmptyState
          v-else-if="upcoming.events.value.length === 0"
          class="mt-3"
          message="Nothing scheduled in the next two weeks."
        />
        <UpcomingList
          v-else
          :events="upcoming.events.value"
          :timezone="project?.timezone ?? 'UTC'"
        />
      </div>
    </div>
  </div>
</template>

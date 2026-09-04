<script setup lang="ts">
import { computed, onBeforeUnmount } from "vue";
import { RouterView, useRoute, useRouter } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProjectContextStore } from "@/stores/project-context";
import { useProjectFinancials } from "@/composables/useProject";
import { useProjectTime } from "@/composables/useProjectTime";
import { useMoney } from "@/composables/useMoney";
import PageContainer from "@/components/ui/PageContainer.vue";
import StatTile from "@/components/ui/StatTile.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import AppButton from "@/components/ui/AppButton.vue";
import ProjectTabs from "./ProjectTabs.vue";

const route = useRoute();
const router = useRouter();
const { project, allowed } = useProjectContext();
const ctxStore = useProjectContextStore();
const projectId = computed(() => String(route.params.projectId));

const { financials, isPending: finPending } = useProjectFinancials(projectId);
const { format } = useMoney();
const time = computed(() => useProjectTime(project.value?.timezone ?? "UTC"));

const dates = computed(() =>
  project.value ? time.value.dateRange(project.value.starts_on, project.value.ends_on) : "",
);
const currency = computed(() => project.value?.currency ?? "GBP");
const archived = computed(() => project.value?.status === "archived");

// ProjectLayout stays mounted while switching tabs / projects (the guard re-hydrates
// context on a projectId change); it only unmounts when leaving the project area.
onBeforeUnmount(() => ctxStore.clear());
</script>

<template>
  <PageContainer>
    <div class="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h1 class="font-display text-[24px] font-semibold tracking-tight">{{ project?.name }}</h1>
        <p class="mt-1 text-[13.5px] text-muted">{{ dates }}</p>
        <p v-if="archived" class="mt-1 text-13 text-amber font-medium">Archived — read only</p>
      </div>
      <div class="flex items-center gap-2">
        <!-- Share is not in this build; shown disabled rather than faked -->
        <AppButton variant="secondary" size="sm" disabled title="Not in this build">Share</AppButton>
        <AppButton
          v-if="allowed('project.settings')"
          variant="secondary"
          size="sm"
          @click="router.push({ name: 'project.settings', params: { projectId } })"
        >
          Project settings
        </AppButton>
      </div>
    </div>

    <!-- stat tiles -->
    <div class="mt-6 border rounded-xl px-6 py-4 flex flex-wrap gap-x-10 gap-y-4 border-line bg-surface">
      <template v-if="finPending">
        <SkeletonBlock v-for="i in 4" :key="i" width="90px" height="44px" />
      </template>
      <template v-else>
        <StatTile
          :value="financials?.total_target_minor != null ? format(financials.total_target_minor, currency) : 'Not set'"
          label="Total budget"
        />
        <StatTile :value="format(financials?.committed_spend_minor ?? 0, currency)" label="Committed" />
        <StatTile
          :value="financials?.remaining_budget_minor != null ? format(financials.remaining_budget_minor, currency) : '—'"
          label="Remaining"
          :tone="
            financials?.remaining_budget_minor != null && financials.remaining_budget_minor < 0 ? 'amber' : 'default'
          "
        />
        <StatTile :value="(financials?.progress_pct ?? 0) + '%'" label="Complete" />
      </template>
    </div>

    <ProjectTabs :project-id="projectId" />

    <div class="mt-7">
      <RouterView />
    </div>
  </PageContainer>
</template>

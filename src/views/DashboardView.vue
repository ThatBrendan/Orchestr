<script setup lang="ts">
import ListPagination from "@/components/ui/ListPagination.vue";
import { computed, ref, onMounted } from "vue";
import NewProjectDialog from "@/components/projects/NewProjectDialog.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { attentionDestination } from "@/lib/attentionDestination";
import { useMyProjects } from "@/composables/useProjects";
import { useMyProfile, useDashboardAttention } from "@/composables/useDashboard";
import PageContainer from "@/components/ui/PageContainer.vue";
import SectionHeading from "@/components/ui/SectionHeading.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import AppButton from "@/components/ui/AppButton.vue";
import ProjectSummaryRow from "@/components/projects/ProjectSummaryRow.vue";
import AttentionRow from "@/components/health/AttentionRow.vue";

const pageTitle = ref<HTMLElement | null>(null);
onMounted(() => pageTitle.value?.focus({ preventScroll: true }));
const showNew = ref(false);
const newProjectButton = ref<InstanceType<typeof AppButton> | null>(null);
function openNewProject(event: MouseEvent) {
  // Give the dialog a reliable return target, including pointer activation.
  (event.currentTarget as HTMLButtonElement).focus();
  showNew.value = true;
}
const { profile } = useMyProfile();
const { activeProjects: projects, isPending, isError, error, refetch } = useMyProjects();
const attention = useDashboardAttention();

const greeting = computed(() => {
  const h = new Date().getHours();
  const part = h < 12 ? "morning" : h < 18 ? "afternoon" : "evening";
  const name = profile.value?.display_name?.split(" ")[0] ?? "there";
  return `Good ${part}, ${name}`;
});

const attentionLine = computed(() => {
  if (attention.isPending.value) return "Checking what needs your attention…";
  if (attention.isError.value) return "Your projects, in one place.";
  const n = attention.totalCount.value;
  if (n === 0) return "Your projects, in one place.";
  return `You have ${n} ${n === 1 ? "thing" : "things"} that need your attention.`;
});
</script>

<template>
  <PageContainer>
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0">
        <h1
          ref="pageTitle"
          tabindex="-1"
          class="text-page-title focus:outline-none"
        >
          {{ greeting }}
        </h1>
        <p class="mt-2 text-sm text-ink-soft">
          {{ attentionLine }}
        </p>
      </div>
      <AppButton
        ref="newProjectButton"
        @click="openNewProject"
      >
        <AppIcon
          name="plus"
          :size="16"
        />New project
      </AppButton>
    </header>

    <!-- needs attention (aggregated — one set-based call) -->
    <div
      v-if="isPending || projects.length || attention.findings.value.length || attention.isError.value"
      class="mt-8"
    >
      <SectionHeading label="Needs attention" />
      <div
        v-if="attention.isPending.value"
        class="mt-3 space-y-2"
      >
        <SkeletonBlock
          v-for="i in 3"
          :key="i"
          height="80px"
          rounded="0.75rem"
        />
      </div>
      <ErrorState
        v-else-if="attention.isError.value"
        class="mt-3"
        :error="attention.error.value"
        :retry="() => attention.refetch()"
      />
      <p
        v-else-if="attention.findings.value.length === 0"
        class="mt-3 flex items-center gap-2 text-sm text-ink-soft"
      >
        <AppIcon
          name="checkCircle"
          :size="18"
          class="shrink-0 text-success"
        />All clear — nothing needs attention across your projects.
      </p>
      <div
        v-else
        class="mt-3 border rounded-xl divide-y border-line bg-surface"
      >
        <AttentionRow
          v-for="(f, i) in attention.findings.value"
          :key="f.project_id + f.code + (f.subject_id ?? '') + i"
          :finding="f"
          :project-label="f.project_name"
          :to="attentionDestination(f.project_id, f).to"
          :destination-label="attentionDestination(f.project_id, f).label"
        />
      </div>
      <ListPagination
        v-if="!attention.isPending.value && !attention.isError.value"
        v-model:page="attention.page.value"
        :previous="attention.canGoPrevious.value"
        :next="attention.canGoNext.value"
        :busy="attention.isFetching.value"
        label="Needs attention pages"
      />
    </div>
    <!-- projects -->
    <section
      aria-label="Projects"
      class="mt-8 space-y-3"
    >
      <SectionHeading label="Projects" />
      <template v-if="isPending">
        <SkeletonBlock
          v-for="i in 2"
          :key="i"
          height="120px"
          rounded="0.75rem"
        />
      </template>
      <ErrorState
        v-else-if="isError"
        :error="error"
        :retry="() => refetch()"
      />
      <EmptyState
        v-else-if="projects.length === 0"
        title="No projects yet"
        message="Create your first project to start planning."
      >
        <template #action>
          <p class="text-sm text-ink-soft">
            Use New project above to get started.
          </p>
        </template>
      </EmptyState>
      <ProjectSummaryRow
        v-for="p in projects"
        v-else
        :key="p.project_id"
        :project="p"
      />
    </section>
    <NewProjectDialog
      :open="showNew"
      @after-close="newProjectButton?.$el.focus()"
      @close="showNew = false"
    />
  </PageContainer>
</template>

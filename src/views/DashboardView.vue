<script setup lang="ts">
import { computed } from "vue";
import { useRouter } from "vue-router";
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

const router = useRouter();
const { profile } = useMyProfile();
const { projects, isPending, isError, error, refetch } = useMyProjects();
const attention = useDashboardAttention();

const greeting = computed(() => {
  const h = new Date().getHours();
  const part = h < 12 ? "morning" : h < 18 ? "afternoon" : "evening";
  const name = profile.value?.display_name?.split(" ")[0] ?? "there";
  return `Good ${part}, ${name}`;
});

const attentionLine = computed(() => {
  if (attention.isPending.value) return "Checking what needs your attention…";
  const n = attention.totalCount.value;
  if (n === 0) return "Nothing needs your attention right now.";
  return `You have ${n} ${n === 1 ? "thing" : "things"} that need your attention.`;
});
</script>

<template>
  <PageContainer>
    <h1 class="font-display text-[26px] font-semibold tracking-tight">
      {{ greeting }}
    </h1>
    <p class="mt-1.5 text-14.5 text-ink-soft">
      {{ attentionLine }}
    </p>

    <!-- projects -->
    <div class="mt-9 space-y-3">
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
          <AppButton @click="router.push({ name: 'projects' })">
            Go to Projects
          </AppButton>
        </template>
      </EmptyState>
      <ProjectSummaryRow
        v-for="p in projects"
        v-else
        :key="p.project_id"
        :project="p"
      />
    </div>

    <!-- needs attention (aggregated — one set-based call) -->
    <div
      v-if="projects.length"
      class="mt-10"
    >
      <SectionHeading label="Needs attention" />
      <div
        v-if="attention.isPending.value"
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
        v-else-if="attention.isError.value"
        class="mt-3"
        :error="attention.error.value"
        :retry="() => attention.refetch()"
      />
      <EmptyState
        v-else-if="attention.findings.value.length === 0"
        class="mt-3"
        message="All clear — nothing needs attention across your projects."
      />
      <div
        v-else
        class="mt-3 border rounded-xl divide-y border-line bg-surface"
      >
        <AttentionRow
          v-for="(f, i) in attention.findings.value"
          :key="f.project_id + f.code + (f.subject_id ?? '') + i"
          :finding="f"
          :project-label="f.project_name"
          :to="{ name: 'project.overview', params: { projectId: f.project_id } }"
        />
      </div>
    </div>
  </PageContainer>
</template>

<script setup lang="ts">
import { computed, ref } from "vue";
import { useMyProjects } from "@/composables/useProjects";
import PageContainer from "@/components/ui/PageContainer.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import ProjectSummaryRow from "@/components/projects/ProjectSummaryRow.vue";
import NewProjectDialog from "@/components/projects/NewProjectDialog.vue";

const { activeProjects, pastProjects, archivedProjects, isPending, isError, error, refetch } = useMyProjects();
const showNew = ref(false);
const group = ref<"active" | "past" | "archived">("active");
const projects = computed(() => group.value === "past" ? pastProjects.value : group.value === "archived" ? archivedProjects.value : activeProjects.value);
const groups = [{ id: "active", label: "Active" }, { id: "past", label: "Past" }, { id: "archived", label: "Archived" }] as const;
</script>

<template>
  <PageContainer>
    <div class="flex items-center justify-between gap-4">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">
          Projects
        </h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">
          Everything you're currently planning.
        </p>
      </div>
      <AppButton @click="showNew = true">
        <AppIcon
          name="plus"
          :size="16"
        />New project
      </AppButton>
    </div>

    <div
      class="mt-6 flex gap-2"
      role="group"
      aria-label="Project group"
    >
      <AppButton
        v-for="tab in groups"
        :key="tab.id"
        :variant="group === tab.id ? 'primary' : 'secondary'"
        :aria-pressed="group === tab.id"
        @click="group = tab.id"
      >
        {{ tab.label }}
      </AppButton>
    </div>
    <div class="mt-6 space-y-3">
      <template v-if="isPending">
        <SkeletonBlock
          v-for="i in 3"
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
        :title="group === 'past' ? 'No past projects yet.' : group === 'archived' ? 'No archived projects.' : 'No active projects yet.'"
        :message="group === 'past' ? 'Completed projects will appear here.' : group === 'archived' ? 'Archived projects remain available here.' : 'Create your first project to start planning.'"
      >
        <template #action>
          <AppButton
            v-if="group === 'active'"
            @click="showNew = true"
          >
            New project
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

    <NewProjectDialog
      :open="showNew"
      @close="showNew = false"
    />
  </PageContainer>
</template>

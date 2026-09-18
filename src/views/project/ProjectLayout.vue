<script setup lang="ts">
import { useQuery } from "@tanstack/vue-query";
import { useAuth } from "@/composables/useAuth";
import { qk } from "@/composables/keys";
import { getMyMembership } from "@/services/members";
import { computed, onBeforeUnmount, ref, watch } from "vue";
import { RouterView, useRoute, useRouter } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProjectContextStore } from "@/stores/project-context";
import { useProject } from "@/composables/useProject";
import { useProjectTime } from "@/composables/useProjectTime";
import { profileDefinition } from "@/lib/projectProfiles";
import PageContainer from "@/components/ui/PageContainer.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppModal from "@/components/ui/AppModal.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import ProjectTabs from "./ProjectTabs.vue";
import ProjectSettingsView from "./ProjectSettingsView.vue";
import { useCommitments } from "@/composables/useCommitments";
import { useMemberDirectory } from "@/composables/useProject";
import { downloadProjectCsv } from "@/lib/projectExport";
import { useToast } from "@/composables/useToast";

const route = useRoute();
const router = useRouter();
const { project, allowed } = useProjectContext();
const ctxStore = useProjectContextStore();
const projectId = computed(() => String(route.params.projectId));

const { userId } = useAuth();
const membership = useQuery({
  queryKey: computed(() => qk.project.membership(projectId.value, userId.value ?? "")),
  queryFn: () => getMyMembership(projectId.value, userId.value!),
  enabled: computed(() => !!userId.value),
});
watch(membership.data, (next) => {
  if (next && ctxStore.context?.projectId === next.project_id) {
    ctxStore.set({ ...ctxStore.context, role: next.role, memberId: next.id });
  } else if (next === null) {
    ctxStore.clear();
    void router.replace({ name: "projects" });
  }
});
const { project: liveProject } = useProject(projectId);
watch(liveProject, (next) => {
  if (next && ctxStore.context?.projectId === next.id) {
    ctxStore.set({ ...ctxStore.context, project: { ...next, module_visibility: next.module_visibility as Record<string, boolean> } });
  }
});

const time = computed(() => useProjectTime(project.value?.timezone ?? "UTC"));

const dates = computed(() =>
  project.value ? time.value.dateRange(project.value.starts_on, project.value.ends_on) : "",
);
const currency = computed(() => project.value?.currency ?? "GBP");
const archived = computed(() => project.value?.status === "archived");
const profileLabel = computed(() => profileDefinition(project.value?.profile).label);
const { commitments } = useCommitments(projectId);
const { members } = useMemberDirectory(projectId);
const toast = useToast();
const settingsOpen = ref(false);
const exporting = ref(false);
watch(()=>route.query.settings,value=>{if(value==='1'&&allowed('project.settings'))settingsOpen.value=true;},{immediate:true});
watch(settingsOpen,value=>{if(!value&&route.query.settings){const query={...route.query};delete query.settings;void router.replace({query});}});

async function exportProject() {
  if (!project.value || exporting.value) return;
  exporting.value = true;
  try {
    await downloadProjectCsv(project.value, commitments.value, members.value, currency.value);
    toast.success("Project export downloaded.");
  } catch (error) {
    toast.error(error instanceof Error ? error.message : "The project export could not be created.");
  } finally {
    exporting.value = false;
  }
}

// ProjectLayout stays mounted while switching tabs / projects (the guard re-hydrates
// context on a projectId change); it only unmounts when leaving the project area.
onBeforeUnmount(() => ctxStore.clear());
</script>

<template>
  <PageContainer>
    <div class="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h1 class="font-display text-[24px] font-semibold tracking-tight">
          {{ project?.name }}
        </h1>
        <p class="mt-1 text-[13.5px] text-muted">
          {{ dates }}
        </p>
        <p class="mt-1 text-13 text-muted">
          {{ profileLabel }}
        </p>
        <p
          v-if="archived"
          class="mt-1 text-13 text-amber font-medium"
        >
          Archived — read only
        </p>
      </div>
      <div class="flex items-center gap-2">
        <AppButton
          variant="secondary"
          size="sm"
          :loading="exporting"
          @click="exportProject"
        >
          Export
        </AppButton>
        <AppButton
          v-if="allowed('project.settings')"
          variant="secondary"
          size="sm"
          aria-label="Open project settings"
          title="Project settings"
          @click="settingsOpen = true"
        >
          <AppIcon
            name="settings"
            :size="16"
          />
        </AppButton>
      </div>
    </div>

    <ProjectTabs :project-id="projectId" />

    <div class="mt-7">
      <RouterView :key="projectId + String(route.name)" />
    </div>

    <AppModal
      :open="settingsOpen"
      title="Project settings"
      size="lg"
      @close="settingsOpen = false"
    >
      <ProjectSettingsView />
    </AppModal>
  </PageContainer>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProjectContextStore } from "@/stores/project-context";
import { useProject } from "@/composables/useProject";
import { useUpdateProject, useSetProjectStatus, useDeleteProject } from "@/composables/useProjects";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import { PROJECT_PROFILES, isProjectModuleVisible, profileDefinition, setModuleVisibility } from "@/lib/projectProfiles";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import SectionHeading from "@/components/ui/SectionHeading.vue";
import type { ProjectProfile, ProjectStatus } from "@/types/database";
import type { Project } from "@/types/domain";

const route = useRoute();
const router = useRouter();
const projectId = computed(() => String(route.params.projectId));
const { allowed, context } = useProjectContext();
const ctxStore = useProjectContextStore();
const { project } = useProject(projectId);
const toast = useToast();

const canEdit = computed(() => allowed("project.settings"));
const canArchive = computed(() => allowed("project.archive"));
const canDelete = computed(() => allowed("project.delete") && project.value?.status !== "archived");

const update = useUpdateProject(projectId.value);
const setStatus = useSetProjectStatus(projectId.value);
const del = useDeleteProject(projectId.value);

const form = reactive({
  name: "",
  description: "",
  starts_on: "",
  ends_on: "",
  profile: "blank" as ProjectProfile,
  budget_visible: true,
});
const fieldError = ref<string | null>(null);
const workspaceError = ref<string | null>(null);
watch(
  project,
  (p) => {
    if (!p) return;
    form.name = p.name;
    form.description = p.description ?? "";
    form.starts_on = p.starts_on ?? "";
    form.ends_on = p.ends_on ?? "";
    form.profile = p.profile;
    form.budget_visible = isProjectModuleVisible(p.profile, p.module_visibility, "budget");
  },
  { immediate: true },
);

function syncContext(nextProject: Project) {
  if (!context.value || context.value.projectId !== nextProject.id) return;
  ctxStore.set({
    ...context.value,
    project: {
      id: nextProject.id,
      name: nextProject.name,
      status: nextProject.status,
      profile: nextProject.profile,
      module_visibility: nextProject.module_visibility as Record<string, boolean>,
      starts_on: nextProject.starts_on,
      ends_on: nextProject.ends_on,
      timezone: nextProject.timezone,
      currency: nextProject.currency,
    },
  });
}

async function saveDetails() {
  if (update.isPending.value || project.value?.status === "archived") return;
  fieldError.value = null;
  if (!form.name.trim()) {
    fieldError.value = "The project needs a name.";
    return;
  }
  if (form.starts_on && form.ends_on && form.ends_on < form.starts_on) {
    fieldError.value = "The end date must be on or after the start date.";
    return;
  }
  try {
    const saved = await update.mutateAsync({
      name: form.name.trim(),
      description: form.description.trim() || null,
      starts_on: form.starts_on || null,
      ends_on: form.ends_on || null,
    });
    syncContext(saved);
    toast.success("Project details saved.");
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}

function onProfileChange() {
  form.budget_visible = isProjectModuleVisible(form.profile, null, "budget");
}

async function saveWorkspace() {
  if (update.isPending.value || project.value?.status === "archived") return;
  workspaceError.value = null;
  if (!project.value) return;
  try {
    const saved = await update.mutateAsync({
      profile: form.profile,
      module_visibility: setModuleVisibility(project.value.module_visibility, "budget", form.budget_visible),
    });
    syncContext(saved);
    toast.success("Workspace settings saved.");
  } catch (e) {
    workspaceError.value = toAppError(e).message;
  }
}

const confirmLifecycle = ref<"complete" | "reopen" | null>(null);
async function changeStatus(status: ProjectStatus, from?: ProjectStatus) {
  if (setStatus.isPending.value || !canArchive.value) return;
  try {
    const saved = await setStatus.mutateAsync({ status, from });
    syncContext(saved);
    confirmLifecycle.value = null;
    toast.success(status === "completed" ? "Project completed. Find it in Past Projects." : status === "archived" ? "Project archived." : "Project is active.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

const confirmDelete = ref(false);
async function doDelete() {
  try {
    await del.mutateAsync();
    toast.success("Project deleted.");
    confirmDelete.value = false;
    await router.push({ name: "projects" });
  } catch (e) {
    toast.error(toAppError(e).message);
    confirmDelete.value = false;
  }
}

const status = computed(() => project.value?.status);
</script>

<template>
  <div class="fade-in max-w-xl space-y-8">
    <div
      v-if="!canEdit"
      class="border rounded-xl p-4 border-line bg-surface text-14 text-ink-soft"
    >
      Only an organizer can change project settings.
    </div>

    <template v-else>
      <div>
        <SectionHeading label="Details" />
        <form
          class="mt-3 space-y-4"
          @submit.prevent="saveDetails"
        >
          <label class="block">
            <span class="text-13 font-medium block mb-1.5 text-ink-soft">Name</span>
            <input
              v-model="form.name"
              required
              class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line"
            >
          </label>
          <label class="block">
            <span class="text-13 font-medium block mb-1.5 text-ink-soft">Description</span>
            <textarea
              v-model="form.description"
              rows="3"
              class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line"
            />
          </label>
          <div class="grid grid-cols-2 gap-3">
            <label class="block">
              <span class="text-13 font-medium block mb-1.5 text-ink-soft">Start date</span>
              <input
                v-model="form.starts_on"
                type="date"
                class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line"
              >
            </label>
            <label class="block">
              <span class="text-13 font-medium block mb-1.5 text-ink-soft">End date</span>
              <input
                v-model="form.ends_on"
                type="date"
                class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line"
              >
            </label>
          </div>
          <p class="text-13 text-muted">
            Currency is {{ project?.currency }} — locked once activities or payments exist.
          </p>
          <p
            v-if="fieldError"
            class="text-13 text-danger"
          >
            {{ fieldError }}
          </p>
          <AppButton
            size="sm"
            :loading="update.isPending.value"
            :disabled="status === 'archived'"
            @click="saveDetails"
          >
            Save changes
          </AppButton>
        </form>
      </div>

      <div>
        <SectionHeading label="Workspace" />
        <div class="mt-3 space-y-4 rounded-xl border border-line bg-surface p-4">
          <label class="block">
            <span class="text-13 font-medium block mb-1.5 text-ink-soft">Project profile</span>
            <select
              v-model="form.profile"
              class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface"
              @change="onProfileChange"
            >
              <option
                v-for="profileOption in PROJECT_PROFILES"
                :key="profileOption.value"
                :value="profileOption.value"
              >
                {{ profileOption.label }}
              </option>
            </select>
            <span class="text-13 text-muted mt-1 block">{{ profileDefinition(form.profile).description }}</span>
          </label>
          <label class="flex items-center gap-2 text-13.5 text-ink-soft">
            <input
              v-model="form.budget_visible"
              type="checkbox"
              class="rounded border-line"
            >
            Show Budget module in this project
          </label>
          <p class="text-13 text-muted">
            Changing this only affects navigation and workspace emphasis. Existing data is preserved.
          </p>
          <p
            v-if="workspaceError"
            class="text-13 text-danger"
          >
            {{ workspaceError }}
          </p>
          <AppButton
            size="sm"
            :loading="update.isPending.value"
            :disabled="status === 'archived'"
            @click="saveWorkspace"
          >
            Save workspace
          </AppButton>
        </div>
      </div>

      <div>
        <SectionHeading label="Status" />
        <p class="mt-2 text-14 text-ink-soft">
          Current status: <span class="font-medium capitalize">{{ status }}</span>
        </p>
        <div class="mt-3 flex flex-wrap gap-2">
          <AppButton
            v-if="status === 'draft' && canArchive"
            variant="secondary"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="changeStatus('active', 'draft')"
          >
            Activate project
          </AppButton>
          <AppButton
            v-if="status === 'active' && canArchive"
            variant="secondary"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="confirmLifecycle = 'complete'"
          >
            Complete project
          </AppButton>
          <AppButton
            v-if="status !== 'archived' && canArchive"
            variant="secondary"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="changeStatus('archived')"
          >
            Archive project
          </AppButton>
          <AppButton
            v-if="status === 'archived' && canArchive"
            variant="secondary"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="changeStatus('active')"
          >
            Unarchive
          </AppButton>
          <AppButton
            v-if="status === 'completed' && canArchive"
            variant="secondary"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="confirmLifecycle = 'reopen'"
          >
            Reopen project
          </AppButton>
        </div>
        <p
          v-if="status === 'archived'"
          class="mt-2 text-13 text-amber"
        >
          Archived projects are read-only until unarchived.
        </p>
      </div>

      <div v-if="canDelete">
        <SectionHeading label="Danger zone" />
        <p class="mt-2 text-13 text-muted">
          Deleting removes this project from everyone's list. It cannot be undone from the app.
        </p>
        <AppButton
          class="mt-3 !text-danger"
          variant="secondary"
          size="sm"
          @click="confirmDelete = true"
        >
          Delete project
        </AppButton>
      </div>
    </template>

    <AppConfirmDialog
      :open="confirmLifecycle !== null"
      :title="confirmLifecycle === 'complete' ? 'Complete this project?' : 'Reopen this project?'"
      :message="confirmLifecycle === 'complete' ? 'This will move the project to Past Projects. You can reopen it later if needed.' : 'This will return the project to Active Projects.'"
      :confirm-label="confirmLifecycle === 'complete' ? 'Complete project' : 'Reopen project'"
      :loading="setStatus.isPending.value"
      @close="confirmLifecycle = null"
      @confirm="confirmLifecycle === 'complete' ? changeStatus('completed', 'active') : changeStatus('active', 'completed')"
    />
    <AppConfirmDialog
      :open="confirmDelete"
      title="Delete project"
      :message="`Delete '${project?.name ?? 'this project'}'? Everyone will lose access. This can't be undone from the app.`"
      confirm-label="Delete project"
      danger
      :loading="del.isPending.value"
      @close="confirmDelete = false"
      @confirm="doDelete"
    />
  </div>
</template>

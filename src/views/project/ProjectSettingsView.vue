<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProject } from "@/composables/useProject";
import { useUpdateProject, useSetProjectStatus, useDeleteProject } from "@/composables/useProjects";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import SectionHeading from "@/components/ui/SectionHeading.vue";

const route = useRoute();
const router = useRouter();
const projectId = computed(() => String(route.params.projectId));
const { allowed } = useProjectContext();
const { project } = useProject(projectId);
const toast = useToast();

const canEdit = computed(() => allowed("project.settings"));
const canArchive = computed(() => allowed("project.archive"));
const canDelete = computed(() => allowed("project.delete"));

const update = useUpdateProject(projectId.value);
const setStatus = useSetProjectStatus(projectId.value);
const del = useDeleteProject(projectId.value);

const form = reactive({ name: "", description: "", starts_on: "", ends_on: "" });
const fieldError = ref<string | null>(null);
watch(
  project,
  (p) => {
    if (!p) return;
    form.name = p.name;
    form.description = p.description ?? "";
    form.starts_on = p.starts_on ?? "";
    form.ends_on = p.ends_on ?? "";
  },
  { immediate: true },
);

async function saveDetails() {
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
    await update.mutateAsync({
      name: form.name.trim(),
      description: form.description.trim() || null,
      starts_on: form.starts_on || null,
      ends_on: form.ends_on || null,
    });
    toast.success("Project details saved.");
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}

async function changeStatus(status: "active" | "archived" | "completed") {
  try {
    await setStatus.mutateAsync(status);
    toast.success(status === "archived" ? "Project archived." : `Project marked as ${status}.`);
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
    <div v-if="!canEdit" class="border rounded-xl p-4 border-line bg-surface text-14 text-ink-soft">
      Only an organizer can change project settings.
    </div>

    <template v-else>
      <div>
        <SectionHeading label="Details" />
        <form class="mt-3 space-y-4" @submit.prevent="saveDetails">
          <label class="block">
            <span class="text-13 font-medium block mb-1.5 text-ink-soft">Name</span>
            <input v-model="form.name" required class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
          </label>
          <label class="block">
            <span class="text-13 font-medium block mb-1.5 text-ink-soft">Description</span>
            <textarea v-model="form.description" rows="3" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
          </label>
          <div class="grid grid-cols-2 gap-3">
            <label class="block">
              <span class="text-13 font-medium block mb-1.5 text-ink-soft">Start date</span>
              <input v-model="form.starts_on" type="date" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line" />
            </label>
            <label class="block">
              <span class="text-13 font-medium block mb-1.5 text-ink-soft">End date</span>
              <input v-model="form.ends_on" type="date" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line" />
            </label>
          </div>
          <p class="text-13 text-muted">Currency is {{ project?.currency }} — locked once activities or payments exist.</p>
          <p v-if="fieldError" class="text-13 text-danger">{{ fieldError }}</p>
          <AppButton size="sm" :loading="update.isPending.value" @click="saveDetails">Save changes</AppButton>
        </form>
      </div>

      <div>
        <SectionHeading label="Status" />
        <p class="mt-2 text-14 text-ink-soft">Current status: <span class="font-medium capitalize">{{ status }}</span></p>
        <div class="mt-3 flex flex-wrap gap-2">
          <AppButton v-if="status === 'active' && canArchive" variant="secondary" size="sm" :loading="setStatus.isPending.value" @click="changeStatus('completed')">
            Mark completed
          </AppButton>
          <AppButton v-if="status !== 'archived' && canArchive" variant="secondary" size="sm" :loading="setStatus.isPending.value" @click="changeStatus('archived')">
            Archive project
          </AppButton>
          <AppButton v-if="status === 'archived' && canArchive" variant="secondary" size="sm" :loading="setStatus.isPending.value" @click="changeStatus('active')">
            Unarchive
          </AppButton>
          <AppButton v-if="status === 'completed' && canArchive" variant="secondary" size="sm" :loading="setStatus.isPending.value" @click="changeStatus('active')">
            Reopen
          </AppButton>
        </div>
        <p v-if="status === 'archived'" class="mt-2 text-13 text-amber">Archived projects are read-only until unarchived.</p>
      </div>

      <div v-if="canDelete">
        <SectionHeading label="Danger zone" />
        <p class="mt-2 text-13 text-muted">Deleting removes this project from everyone's list. It cannot be undone from the app.</p>
        <AppButton class="mt-3 !text-danger" variant="secondary" size="sm" @click="confirmDelete = true">Delete project</AppButton>
      </div>
    </template>

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

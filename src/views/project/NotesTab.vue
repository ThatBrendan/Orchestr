<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute } from "vue-router";
import { useProject } from "@/composables/useProject";
import { useProjectContext } from "@/composables/useProjectContext";
import { useUpdateProject } from "@/composables/useProjects";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import AppButton from "@/components/ui/AppButton.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";

const NOTES_LIMIT = 10000;

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project: contextProject, allowed } = useProjectContext();
const { project, isPending, isError, error } = useProject(projectId);
const update = useUpdateProject(projectId.value);
const toast = useToast();

const draft = ref("");
const isEditing = ref(false);
const fieldError = ref<string | null>(null);
const archived = computed(() => contextProject.value?.status === "archived");
const canEdit = computed(() => allowed("project.settings") && !archived.value);
const characterCount = computed(() => draft.value.length);
const isTooLong = computed(() => characterCount.value > NOTES_LIMIT);
const savedNotes = computed(() => project.value?.notes ?? "");
const hasSavedNotes = computed(() => savedNotes.value.length > 0);
const hasChanges = computed(() => draft.value !== savedNotes.value);

watch(
  () => project.value?.notes,
  (notes) => {
    if (!isEditing.value) draft.value = notes ?? "";
  },
  { immediate: true },
);

function beginEdit() {
  draft.value = savedNotes.value;
  fieldError.value = null;
  isEditing.value = true;
}

function cancelEdit() {
  draft.value = savedNotes.value;
  fieldError.value = null;
  isEditing.value = false;
}

async function saveNotes() {
  fieldError.value = null;
  if (isTooLong.value) {
    fieldError.value = `Notes must be ${NOTES_LIMIT.toLocaleString()} characters or fewer.`;
    return;
  }

  try {
    await update.mutateAsync({ notes: draft.value.length > 0 ? draft.value : null });
    toast.success("Notes saved.");
    isEditing.value = false;
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}
</script>

<template>
  <div class="fade-in max-w-3xl">
    <div class="mb-5 flex items-start justify-between gap-4">
      <div>
        <h2 class="text-18 font-semibold text-ink">Notes</h2>
        <p class="mt-1 text-14 text-ink-soft">
          Keep useful information about this project that doesn't belong to a specific activity.
        </p>
      </div>
      <AppButton v-if="canEdit && !isEditing" size="sm" @click="beginEdit">Edit</AppButton>
    </div>

    <div v-if="isPending" class="space-y-3">
      <SkeletonBlock height="180px" rounded="0.75rem" />
    </div>
    <ErrorState v-else-if="isError" :error="error" />

    <template v-else>
      <div v-if="isEditing" class="space-y-3">
        <textarea
          v-model="draft"
          class="min-h-[280px] w-full resize-y rounded-xl border border-line bg-surface px-3.5 py-3 text-14 leading-6 text-ink focus-ring"
          :maxlength="NOTES_LIMIT + 1"
          aria-label="Project notes"
        />
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p class="text-13" :class="isTooLong ? 'text-danger' : 'text-muted'">
              {{ characterCount.toLocaleString() }} / {{ NOTES_LIMIT.toLocaleString() }} characters
            </p>
            <p v-if="fieldError" class="mt-1 text-13 text-danger">{{ fieldError }}</p>
          </div>
          <div class="flex gap-2">
            <AppButton variant="secondary" size="sm" :disabled="update.isPending.value" @click="cancelEdit">Cancel</AppButton>
            <AppButton
              size="sm"
              :loading="update.isPending.value"
              :disabled="isTooLong || !hasChanges || update.isPending.value"
              @click="saveNotes"
            >
              Save
            </AppButton>
          </div>
        </div>
      </div>

      <div v-else-if="hasSavedNotes" class="rounded-xl border border-line bg-surface p-4">
        <p class="whitespace-pre-wrap text-14 leading-6 text-ink-soft">{{ savedNotes }}</p>
      </div>

      <EmptyState v-else message="No project notes yet.">
        <template v-if="canEdit" #action>
          <AppButton size="sm" @click="beginEdit">Add notes</AppButton>
        </template>
      </EmptyState>

      <p v-if="archived" class="mt-3 text-13 text-amber">Archived projects are read-only until unarchived.</p>
      <p v-else-if="!canEdit" class="mt-3 text-13 text-muted">Only an organizer can edit project notes.</p>
    </template>
  </div>
</template>

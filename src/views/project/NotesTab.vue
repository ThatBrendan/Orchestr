<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import { useRoute } from "vue-router";
import { useProjectNotes } from "@/composables/useProjectNotes";
import { useProjectContext } from "@/composables/useProjectContext";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import type { ProjectNote } from "@/types/domain";
import AppButton from "@/components/ui/AppButton.vue";
import AppModal from "@/components/ui/AppModal.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project, context, isOrganizer, allowed } = useProjectContext();
const { list, save, remove } = useProjectNotes(projectId);
const toast = useToast();
const notes = computed(() => list.data.value ?? []);
const archived = computed(() => project.value?.status === "archived");
const canCreate = computed(() => allowed("note.create") && !archived.value);
const atLimit = computed(() => notes.value.length >= 20);
const busy = computed(() => save.isPending.value || remove.isPending.value);
const dialogOpen = ref(false);
const editingId = ref<string>();
const draft = reactive({ title: "", body: "" });
const fieldError = ref("");
const deleting = ref<ProjectNote | null>(null);
const expanded = ref(new Set<string>());
const titleCount = computed(() => Array.from(draft.title).length);
const bodyCount = computed(() => Array.from(draft.body).length);
const valid = computed(() => !!draft.title.trim() && !!draft.body.trim() && titleCount.value <= 120 && bodyCount.value <= 10000);
function canManage(note: ProjectNote) {
  return canCreate.value && (isOrganizer.value || (!!note.created_by && note.created_by === context.value?.memberId));
}
function beginEdit(note?: ProjectNote) {
  editingId.value = note?.id;
  draft.title = note?.title ?? "";
  draft.body = note?.body ?? "";
  fieldError.value = "";
  dialogOpen.value = true;
}
watch(projectId, () => { dialogOpen.value = false; deleting.value = null; expanded.value = new Set(); });
async function submit() {
  if (busy.value || !valid.value) return;
  fieldError.value = "";
  try {
    await save.mutateAsync({ projectId: projectId.value, id: editingId.value, title: draft.title.trim(), body: draft.body.trim() });
    dialogOpen.value = false;
    toast.success("Note saved.");
  } catch (error) { fieldError.value = toAppError(error).message; }
}
async function confirmDelete() {
  if (!deleting.value || busy.value) return;
  try {
    await remove.mutateAsync({ id: deleting.value.id, projectId: deleting.value.project_id });
    deleting.value = null;
    toast.success("Note deleted.");
  } catch (error) { toast.error(toAppError(error).message); }
}
function toggle(id: string) {
  const next = new Set(expanded.value);
  if (next.has(id)) next.delete(id); else next.add(id);
  expanded.value = next;
}
const date = (value: string) => new Date(value).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
</script>

<template>
  <div class="fade-in max-w-3xl">
    <div class="mb-5 flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0 flex-1">
        <h2 class="text-18 font-semibold text-ink">
          Notes
        </h2>
        <p class="mt-1 text-14 text-ink-soft">
          Keep useful information about this project that doesn't belong to a specific activity.
        </p>
      </div>
      <AppButton
        v-if="canCreate"
        size="sm"
        :disabled="atLimit || list.isPending.value || list.isError.value || busy"
        @click="beginEdit()"
      >
        + Add note
      </AppButton>
    </div>
    <SkeletonBlock
      v-if="list.isPending.value"
      height="180px"
      rounded="0.75rem"
    />
    <ErrorState
      v-else-if="list.isError.value"
      :error="list.error.value"
      :retry="() => list.refetch()"
    />
    <template v-else>
      <p
        v-if="atLimit && canCreate"
        role="status"
        class="mb-4 text-13 text-muted"
      >
        You've reached the 20-note limit for this project.
      </p>
      <EmptyState
        v-if="!notes.length"
        message="No project notes yet."
      />
      <div
        v-else
        class="space-y-4"
      >
        <article
          v-for="note in notes"
          :key="note.id"
          class="min-w-0 rounded-xl border border-line bg-surface p-4"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0 flex-1">
              <h3 class="font-semibold text-14 [overflow-wrap:anywhere]">
                {{ note.title }}
              </h3>
              <p class="mt-1 text-13 text-muted">
                {{ note.creator_name ?? 'Unknown author' }} · <time :datetime="note.created_at">{{ date(note.created_at) }}</time>
                <span v-if="note.updated_at !== note.created_at"> · Edited <time :datetime="note.updated_at">{{ date(note.updated_at) }}</time></span>
              </p>
            </div>
            <div
              v-if="canManage(note)"
              class="flex gap-2"
            >
              <AppButton
                variant="secondary"
                size="sm"
                :disabled="busy"
                @click="beginEdit(note)"
              >
                Edit
              </AppButton>
              <AppButton
                variant="secondary"
                size="sm"
                :disabled="busy"
                @click="deleting = note"
              >
                Delete
              </AppButton>
            </div>
          </div>
          <p
            :id="`note-body-${note.id}`"
            class="mt-3 whitespace-pre-wrap text-14 leading-6 text-ink-soft [overflow-wrap:anywhere]"
            :class="expanded.has(note.id) ? 'max-h-96 overflow-y-auto' : (note.body.length > 240 || note.body.split('\n').length > 6 ? 'line-clamp-6' : '')"
          >
            {{ note.body }}
          </p>
          <button
            v-if="note.body.length > 240 || note.body.split('\n').length > 6"
            class="mt-2 text-13 text-accent focus-ring"
            :aria-expanded="expanded.has(note.id)"
            :aria-controls="`note-body-${note.id}`"
            @click="toggle(note.id)"
          >
            {{ expanded.has(note.id) ? 'Show less' : 'Show more' }}
          </button>
        </article>
      </div>
      <p class="mt-3 text-13 text-muted">
        {{ notes.length }} / 20 notes
      </p>
    </template>
    <p
      v-if="archived"
      class="mt-3 text-13 text-amber"
    >
      Archived projects are read-only until unarchived.
    </p>
    <p
      v-else-if="!canCreate"
      class="mt-3 text-13 text-muted"
    >
      You have read-only access to project notes.
    </p>

    <AppModal
      :open="dialogOpen"
      :busy="busy"
      :title="editingId ? 'Edit note' : 'Add note'"
      size="lg"
      @close="dialogOpen = false"
    >
      <form
        id="project-note-form"
        class="space-y-4"
        @submit.prevent="submit"
      >
        <label class="block text-14">
          <span class="block mb-1.5 font-medium">Title</span>
          <input
            v-model="draft.title"
            required
            class="w-full rounded-lg border border-line px-3 py-2 focus-ring"
            :disabled="busy"
            aria-describedby="note-title-count"
          >
        </label>
        <p
          id="note-title-count"
          class="text-13"
          :class="titleCount > 120 ? 'text-danger' : 'text-muted'"
        >
          {{ titleCount }} / 120 characters
        </p>
        <label class="block text-14">
          <span class="block mb-1.5 font-medium">Note</span>
          <textarea
            v-model="draft.body"
            required
            rows="8"
            class="w-full resize-y rounded-lg border border-line px-3 py-2 focus-ring"
            :disabled="busy"
            aria-describedby="note-body-count"
          />
        </label>
        <p
          id="note-body-count"
          class="text-13"
          :class="bodyCount > 10000 ? 'text-danger' : 'text-muted'"
        >
          {{ bodyCount }} / 10,000 characters
        </p>
        <p
          v-if="fieldError"
          role="alert"
          class="text-13 text-danger"
        >
          {{ fieldError }}
        </p>
      </form>
      <template #footer>
        <AppButton
          variant="secondary"
          size="sm"
          :disabled="busy"
          @click="dialogOpen = false"
        >
          Cancel
        </AppButton>
        <AppButton
          size="sm"
          :loading="save.isPending.value"
          :disabled="!valid || busy"
          @click="submit"
        >
          Save note
        </AppButton>
      </template>
    </AppModal>
    <AppConfirmDialog
      :open="!!deleting"
      title="Delete note"
      :message="`Delete “${deleting?.title ?? ''}”? It will be removed from project notes.`"
      confirm-label="Delete note"
      danger
      :loading="remove.isPending.value"
      @close="deleting = null"
      @confirm="confirmDelete"
    />
  </div>
</template>

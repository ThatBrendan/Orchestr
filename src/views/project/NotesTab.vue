<script setup lang="ts">
import { useExecutionDialogFocus } from "@/composables/useExecutionDialogFocus";
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
const selectedId = ref<string | null>(null);
const selectedNote = computed(() => notes.value.find((note) => note.id === selectedId.value) ?? null);
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
watch(projectId, () => { dialogOpen.value = false; deleting.value = null; selectedId.value = null; });
watch(notes, (value) => {
  if (!value.length) {
    selectedId.value = null;
  } else if (!value.some((note) => note.id === selectedId.value)) {
    selectedId.value = value[0]?.id ?? null;
  }
}, { immediate: true });
async function submit() {
  if (busy.value || !valid.value) return;
  fieldError.value = "";
  try {
    const result = await save.mutateAsync({ projectId: projectId.value, id: editingId.value, title: draft.title.trim(), body: draft.body.trim() });
    await list.refetch();
    if (!editingId.value && typeof result === "string") selectedId.value = result;
    else if (editingId.value) selectedId.value = editingId.value;
    dialogOpen.value = false;
    toast.success("Note saved.");
  } catch (error) { fieldError.value = toAppError(error).message; }
}
async function confirmDelete() {
  if (!deleting.value || busy.value) return;
  const deleted = deleting.value;
  const index = notes.value.findIndex((note) => note.id === deleted.id);
  try {
    await remove.mutateAsync({ id: deleted.id, projectId: deleted.project_id });
    deleting.value = null;
    await list.refetch();
    const remaining = notes.value;
    selectedId.value = remaining[Math.min(index, remaining.length - 1)]?.id ?? null;
    toast.success("Note deleted.");
  } catch (error) { toast.error(toAppError(error).message); }
}
const preview = (body: string) => {
  const compact = body.replace(/\s+/g, " ").trim();
  return compact.length > 120 ? `${compact.slice(0, 117)}...` : compact;
};
const date = (value: string) => new Date(value).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
const focusFallback = ref<HTMLElement | null>(null);
const restoreDialogFocus = useExecutionDialogFocus(computed(() => dialogOpen.value || !!deleting.value), focusFallback);
</script>

<template>
  <div class="fade-in max-w-6xl">
    <div class="mb-5 flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0 flex-1">
        <h2
          ref="focusFallback"
          tabindex="-1"
          class="text-section-heading focus-ring"
        >
          Notes
        </h2>
      </div>
      <AppButton
        v-if="canCreate"
        size="sm"
        :disabled="atLimit || list.isPending.value || list.isError.value || busy"
        @click="beginEdit()"
      >
        Add note
      </AppButton>
    </div>
    <div
      v-if="list.isPending.value"
      role="status"
      aria-label="Loading notes"
      class="grid gap-5 lg:grid-cols-[minmax(240px,38%)_minmax(0,1fr)]"
    >
      <div class="space-y-3">
        <SkeletonBlock
          v-for="i in 3"
          :key="i"
          height="104px"
          rounded="0.75rem"
        />
      </div>
      <SkeletonBlock
        height="360px"
        rounded="0.75rem"
      />
    </div>
    <ErrorState
      v-else-if="list.isError.value"
      :error="list.error.value"
      :retry="() => list.refetch()"
    />
    <template v-else>
      <p
        v-if="atLimit && canCreate"
        role="status"
        class="mb-4 text-meta text-muted"
      >
        You've reached the 20-note limit for this project.
      </p>
      <EmptyState
        v-if="!notes.length"
        message="No notes yet."
      >
        <template #action>
          <AppButton
            v-if="canCreate"
            size="sm"
            :disabled="atLimit || busy"
            @click="beginEdit()"
          >
            Add note
          </AppButton>
        </template>
      </EmptyState>
      <div
        v-else
        class="grid gap-5 lg:grid-cols-[minmax(240px,38%)_minmax(0,1fr)]"
      >
        <nav
          aria-label="Project notes"
          class="min-w-0 rounded-xl border border-line bg-surface lg:max-h-[calc(100vh-220px)] lg:overflow-y-auto"
        >
          <ol>
            <li
              v-for="note in notes"
              :key="note.id"
              class="border-b border-line last:border-b-0"
            >
              <button
                type="button"
                class="group block w-full min-h-24 px-4 py-3 text-left focus-ring [overflow-wrap:anywhere]"
                :class="selectedId === note.id
                  ? 'border-l-4 border-l-brand bg-brand-soft/60'
                  : 'border-l-4 border-l-transparent hover:bg-surface-subtle'"
                :aria-current="selectedId === note.id ? 'true' : undefined"
                :aria-label="note.title"
                @click="selectedId = note.id"
              >
                <span
                  class="block text-card-heading font-semibold"
                  :class="selectedId === note.id ? 'text-brand' : 'text-ink'"
                >
                  {{ note.title }}
                </span>
                <span class="mt-1 block text-sm leading-5 text-ink-soft line-clamp-2">
                  {{ preview(note.body) }}
                </span>
                <span class="mt-2 block text-meta text-muted">
                  Updated <time :datetime="note.updated_at">{{ date(note.updated_at) }}</time>
                </span>
              </button>
            </li>
          </ol>
        </nav>
        <article
          v-if="selectedNote"
          aria-label="Selected note detail"
          class="min-w-0 rounded-xl border border-line bg-surface p-5 sm:p-6"
        >
          <header class="border-b border-line pb-4">
            <h3 class="text-section-heading [overflow-wrap:anywhere]">
              {{ selectedNote.title }}
            </h3>
            <p class="mt-2 text-meta text-muted">
              Updated <time :datetime="selectedNote.updated_at">{{ date(selectedNote.updated_at) }}</time>
            </p>
            <p
              v-if="selectedNote.creator_name"
              class="mt-1 text-meta text-muted"
            >
              By {{ selectedNote.creator_name }}
            </p>
          </header>
          <div class="py-5">
            <p class="max-w-prose whitespace-pre-wrap text-body leading-7 text-ink-soft [overflow-wrap:anywhere]">
              {{ selectedNote.body }}
            </p>
          </div>
          <div
            v-if="canManage(selectedNote)"
            class="flex flex-wrap items-center gap-2 border-t border-line pt-4"
          >
            <AppButton
              variant="secondary"
              :disabled="busy"
              :aria-label="`Edit note: ${selectedNote.title}`"
              @click="beginEdit(selectedNote)"
            >
              Edit
            </AppButton>
            <AppButton
              variant="ghost"
              :disabled="busy"
              :aria-label="`Delete note: ${selectedNote.title}`"
              @click="deleting = selectedNote"
            >
              Delete
            </AppButton>
          </div>
        </article>
      </div>
    </template>
    <p
      v-if="archived"
      class="mt-3 text-meta text-warning"
    >
      Archived projects are read-only until unarchived.
    </p>
    <p
      v-else-if="!canCreate"
      class="mt-3 text-meta text-muted"
    >
      You have read-only access to project notes.
    </p>

    <AppModal
      :open="dialogOpen"
      :busy="busy"
      :title="editingId ? 'Edit note' : 'Add note'"
      size="lg"
      @after-close="restoreDialogFocus"
      @close="dialogOpen = false"
    >
      <form
        id="project-note-form"
        class="space-y-4"
        @submit.prevent="submit"
      >
        <label class="block text-sm">
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
          class="text-meta"
          :class="titleCount > 120 ? 'text-danger' : 'text-muted'"
        >
          {{ titleCount }} / 120 characters
        </p>
        <label class="block text-sm">
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
          class="text-meta"
          :class="bodyCount > 10000 ? 'text-danger' : 'text-muted'"
        >
          {{ bodyCount }} / 10,000 characters
        </p>
        <p
          v-if="fieldError"
          role="alert"
          class="text-meta text-danger"
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
      @after-close="restoreDialogFocus"
      @close="deleting = null"
      @confirm="confirmDelete"
    />
  </div>
</template>

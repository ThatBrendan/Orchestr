<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { DateTime } from "luxon";
import { useCommitmentOccurrences, useCompleteCommitmentOccurrence, useSkipCommitmentOccurrence, useSaveCommitmentOccurrenceNote, useStopCommitmentRecurrence } from "@/composables/useCommitments";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import AppButton from "@/components/ui/AppButton.vue";
import { presentLabel } from "@/lib/presentation";
import AppModal from "@/components/ui/AppModal.vue";
import ErrorState from "@/components/ui/ErrorState.vue";

const props = defineProps<{ projectId: string; commitmentId: string; timezone: string; occurrenceDate?: string; canEdit: boolean; recurrenceActive: boolean }>();
const pid = computed(() => props.projectId);
const cid = computed(() => props.commitmentId);
const selectedDate = ref(props.occurrenceDate ?? "");
const today = () => DateTime.now().setZone(props.timezone).toISODate() ?? "";
const validDate = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value) && DateTime.fromISO(value).isValid;
const start = computed(() => validDate(selectedDate.value) ? selectedDate.value : DateTime.now().setZone(props.timezone).minus({ days: 30 }).toISODate()!);
const end = computed(() => validDate(selectedDate.value) ? selectedDate.value : DateTime.now().setZone(props.timezone).plus({ months: 6 }).toISODate()!);
const { occurrences, isPending, isError, error, refetch } = useCommitmentOccurrences(cid, start, end);
const selected = computed(() => occurrences.value.find((o) => o.occurrence_date === selectedDate.value) ?? null);
watch(() => props.occurrenceDate, (date) => { selectedDate.value = date ?? ""; });
watch(occurrences, (rows) => {
  if (!selectedDate.value) selectedDate.value = (rows.find((o) => o.status === "upcoming" || o.status === "overdue") ?? rows.at(-1))?.occurrence_date ?? "";
});
const complete = useCompleteCommitmentOccurrence(pid, cid);
const skip = useSkipCommitmentOccurrence(pid, cid);
const save = useSaveCommitmentOccurrenceNote(pid, cid);
const stop = useStopCommitmentRecurrence(pid, cid);
const toast = useToast();
const draft = ref("");
const editing = ref(false);
const reason = ref("");
const skipOpen = ref(false);
const stopAfter = ref(today());
const busy = computed(() => complete.isPending.value || skip.isPending.value || save.isPending.value || stop.isPending.value);
const noteLength = computed(() => Array.from(draft.value).length);
const reasonLength = computed(() => Array.from(reason.value.trim()).length);
watch(selectedDate, () => { editing.value = false; skipOpen.value = false; });
function edit() { draft.value = selected.value?.note ?? ""; editing.value = true; }
async function saveNote(clear = false) {
  if (!selected.value || busy.value) return;
  try {
    await save.mutateAsync({ date: selected.value.occurrence_date, note: clear ? null : draft.value.trim() || null });
    editing.value = false;
    toast.success(clear ? "Occurrence note cleared." : "Occurrence note saved.");
  } catch (e) { toast.error(toAppError(e).message); }
}
async function markComplete() {
  if (!selected.value || busy.value) return;
  try { await complete.mutateAsync(selected.value.occurrence_date); toast.success("Occurrence completed."); }
  catch (e) { toast.error(toAppError(e).message); }
}
async function confirmSkip() {
  if (!selected.value || busy.value || !reasonLength.value || reasonLength.value > 500) return;
  try {
    await skip.mutateAsync({ date: selected.value.occurrence_date, reason: reason.value.trim() });
    skipOpen.value = false;
    toast.success("Occurrence skipped.");
  } catch (e) { toast.error(toAppError(e).message); }
}
async function stopSeries() {
  if (busy.value || !validDate(stopAfter.value)) return;
  try { await stop.mutateAsync(stopAfter.value); toast.success("Recurrence stopped."); }
  catch (e) { toast.error(toAppError(e).message); }
}
</script>

<template>
  <section class="rounded-xl border border-line p-4 space-y-3">
    <h3 class="text-14 font-semibold">
      This occurrence
    </h3>
    <label class="block text-13">
      <span class="block mb-1">Occurrence date</span>
      <input
        v-model="selectedDate"
        type="date"
        :disabled="busy || editing"
        class="rounded-lg border border-line px-3 py-2 focus-ring"
      >
    </label>
    <p
      v-if="isPending"
      class="text-13 text-muted"
    >
      Loading occurrence…
    </p>
    <ErrorState
      v-else-if="isError"
      :error="error"
      :retry="() => refetch()"
    />
    <p
      v-else-if="!selected"
      class="text-13 text-muted"
    >
      No occurrence on this date. Choose a date in this series.
    </p>
    <template v-else>
      <p class="text-14">
        Status: {{ presentLabel(selected.status) }}
      </p>
      <div
        v-if="selected.status === 'skipped'"
        class="text-14 whitespace-pre-wrap [overflow-wrap:anywhere]"
      >
        <span class="font-medium">Reason for skipping:</span> {{ selected.skip_reason ?? 'No reason recorded.' }}
      </div>
      <h4 class="text-13 font-medium">
        Occurrence note
      </h4>
      <template v-if="editing">
        <textarea
          v-model="draft"
          rows="5"
          aria-label="Occurrence note"
          :disabled="busy"
          class="w-full border border-line rounded-lg px-3 py-2 text-14 focus-ring"
        />
        <p
          class="text-13"
          :class="noteLength > 10000 ? 'text-danger' : 'text-muted'"
        >
          {{ noteLength }} / 10,000 characters
        </p>
        <div class="flex flex-wrap gap-2">
          <AppButton
            size="sm"
            :disabled="busy || noteLength > 10000"
            @click="saveNote()"
          >
            Save note
          </AppButton>
          <AppButton
            size="sm"
            variant="secondary"
            :disabled="busy"
            @click="editing = false"
          >
            Cancel
          </AppButton>
        </div>
      </template>
      <template v-else>
        <p class="text-14 whitespace-pre-wrap max-h-64 overflow-y-auto [overflow-wrap:anywhere]">
          {{ selected.note ?? 'No note for this occurrence.' }}
        </p>
        <div
          v-if="canEdit"
          class="flex flex-wrap gap-2"
        >
          <AppButton
            size="sm"
            variant="secondary"
            :disabled="busy"
            @click="edit"
          >
            {{ selected.note ? 'Edit note' : 'Add note' }}
          </AppButton>
          <AppButton
            v-if="selected.note"
            size="sm"
            variant="secondary"
            :disabled="busy"
            @click="saveNote(true)"
          >
            Clear note
          </AppButton>
        </div>
      </template>
      <div
        v-if="canEdit"
        class="flex flex-wrap gap-2"
      >
        <AppButton
          v-if="selected.status !== 'completed'"
          size="sm"
          :disabled="busy || editing"
          @click="markComplete"
        >
          Complete occurrence
        </AppButton>
        <AppButton
          v-if="selected.status !== 'skipped'"
          size="sm"
          variant="secondary"
          :disabled="busy || editing"
          @click="reason = ''; skipOpen = true"
        >
          Skip this occurrence
        </AppButton>
      </div>
    </template>
    <div
      v-if="canEdit && recurrenceActive"
      class="pt-3 border-t border-line flex flex-wrap items-end gap-2"
    >
      <label class="text-13"><span class="block mb-1">Stop after</span><input
        v-model="stopAfter"
        type="date"
        :disabled="busy"
        class="rounded-lg border border-line px-3 py-2 focus-ring"
      ></label>
      <AppButton
        size="sm"
        variant="secondary"
        :disabled="busy || editing || !validDate(stopAfter)"
        @click="stopSeries"
      >
        Stop recurrence
      </AppButton>
    </div>
    <AppModal
      :open="skipOpen"
      :busy="busy"
      title="Skip this occurrence"
      @close="skipOpen = false"
    >
      <p class="mb-3 text-14">
        Skip {{ selectedDate }} only. Future occurrences will continue.
      </p>
      <label class="block text-14"><span class="block mb-2">Reason for skipping</span><textarea
        v-model="reason"
        required
        rows="4"
        :disabled="busy"
        class="w-full border border-line rounded-lg px-3 py-2 focus-ring"
      /></label>
      <p
        class="mt-2 text-13"
        :class="reasonLength > 500 ? 'text-danger' : 'text-muted'"
      >
        {{ reasonLength }} / 500 characters
      </p>
      <template #footer>
        <AppButton
          size="sm"
          variant="secondary"
          :disabled="busy"
          @click="skipOpen = false"
        >
          Cancel
        </AppButton>
        <AppButton
          size="sm"
          :disabled="busy || !reasonLength || reasonLength > 500"
          @click="confirmSkip"
        >
          Skip this occurrence
        </AppButton>
      </template>
    </AppModal>
  </section>
</template>

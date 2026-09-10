<script setup lang="ts">
import { computed, ref } from "vue";
import { DateTime } from "luxon";
import {
  useSetCommitmentStatus,
  useDeleteCommitment,
  useParticipants,
  useAddParticipant,
  useRemoveParticipant,
  useCommitmentOccurrences,
  useCompleteCommitmentOccurrence,
  useSkipCommitmentOccurrence,
  useStopCommitmentRecurrence,
} from "@/composables/useCommitments";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import { activityTypeLabel, activityWorkflow, commitmentStatusActions, commitmentStatusLabel } from "@/lib/activityWorkflows";
import { categoryLabel } from "@/lib/commitmentCategories";
import { recurrenceLabel } from "@/lib/recurrence";
import type { Commitment } from "@/services/commitments";
import type { CommitmentStatus } from "@/types/database";
import type { MemberDirectoryEntry } from "@/types/derived";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import AppAvatar from "@/components/ui/AppAvatar.vue";
import PaymentsPanel from "./PaymentsPanel.vue";

const props = defineProps<{
  open: boolean;
  projectId: string;
  currency: string;
  timezone: string;
  commitment: Commitment;
  members: MemberDirectoryEntry[];
  canEdit: boolean;
  canEditPayments: boolean;
  canDelete: boolean;
}>();
const emit = defineEmits<{ close: []; edit: [] }>();

const { format } = useMoney();
const time = useProjectTime(props.timezone);
const toast = useToast();

const setStatus = useSetCommitmentStatus(props.projectId);
const del = useDeleteCommitment(props.projectId);
const { participants, isPending: partPending } = useParticipants(computed(() => props.commitment.id));
const addParticipant = useAddParticipant(props.projectId, props.commitment.id);
const removeParticipant = useRemoveParticipant(props.projectId, props.commitment.id);
const commitmentId = computed(() => props.commitment.id);
const occurrenceStart = computed(() => DateTime.now().setZone(props.timezone).minus({ days: 30 }).toISODate() ?? "");
const occurrenceEnd = computed(() => DateTime.now().setZone(props.timezone).plus({ months: 6 }).toISODate() ?? "");
const { occurrences } = useCommitmentOccurrences(commitmentId, occurrenceStart, occurrenceEnd);
const completeOccurrence = useCompleteCommitmentOccurrence(
  computed(() => props.projectId),
  commitmentId,
);
const skipOccurrence = useSkipCommitmentOccurrence(
  computed(() => props.projectId),
  commitmentId,
);
const stopRecurrence = useStopCommitmentRecurrence(
  computed(() => props.projectId),
  commitmentId,
);

const workflow = computed(() => activityWorkflow(props.commitment.activity_type));
const nextTransitions = computed(() => commitmentStatusActions(props.commitment.activity_type, props.commitment.status));
const statusTone = (s: string) => (s === "cancelled" ? "neutral" : s === "completed" || s === "booked" ? "accent" : "amber");

async function transition(to: CommitmentStatus) {
  try {
    await setStatus.mutateAsync({ id: props.commitment.id, status: to });
    toast.success("Status updated.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

const confirmDelete = ref(false);
async function doDelete() {
  if (del.isPending.value) return;
  try {
    await del.mutateAsync(props.commitment.id);
    toast.success("Activity deleted.");
    confirmDelete.value = false;
    emit("close");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

const participantIds = computed(() => new Set(participants.value.map((p) => p.member_id)));
const addableMembers = computed(() => props.members.filter((m) => m.status === "active" && !participantIds.value.has(m.member_id)));
const selectedNewParticipant = ref("");
async function submitAddParticipant() {
  if (!selectedNewParticipant.value) return;
  try {
    await addParticipant.mutateAsync({
      project_id: props.projectId,
      commitment_id: props.commitment.id,
      member_id: selectedNewParticipant.value,
    });
    selectedNewParticipant.value = "";
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
async function doRemoveParticipant(id: string) {
  try {
    await removeParticipant.mutateAsync(id);
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

function memberName(memberId: string): string {
  return props.members.find((m) => m.member_id === memberId)?.display_name ?? "Unknown";
}

const hasLocation = computed(() => !!(props.commitment.location_label || props.commitment.location_address));
const hasSupplierBooking = computed(
  () =>
    !!(
      props.commitment.supplier_name ||
      props.commitment.supplier_contact ||
      props.commitment.booking_reference ||
      props.commitment.booking_confirmed
    ),
);
const showPayments = computed(() => workflow.value.preferredFields.payments || props.commitment.estimated_cost_minor != null);
const dateStartLabel = computed(() => (props.commitment.activity_type === "task" || props.commitment.activity_type === "purchase" ? "Due" : "Starts"));
const supplierLabel = computed(() => (workflow.value.preferredFields.booking ? "Supplier / booking" : "Supplier"));
const isRecurring = computed(() => props.commitment.recurrence_frequency != null);
const repeatLabel = computed(() =>
  recurrenceLabel(props.commitment.recurrence_frequency, props.commitment.recurrence_interval),
);
const nextOccurrence = computed(() =>
  occurrences.value.find((occurrence) => occurrence.status === "overdue" || occurrence.status === "upcoming") ?? null,
);
const stopAfterDate = ref("");

async function completeNextOccurrence() {
  if (!nextOccurrence.value) return;
  try {
    await completeOccurrence.mutateAsync(nextOccurrence.value.occurrence_date);
    toast.success("Occurrence completed.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

async function skipNextOccurrence() {
  if (!nextOccurrence.value) return;
  try {
    await skipOccurrence.mutateAsync(nextOccurrence.value.occurrence_date);
    toast.success("Occurrence skipped.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

async function stopSeries() {
  const stopAfter = stopAfterDate.value || DateTime.now().setZone(props.timezone).toISODate();
  if (!stopAfter) return;
  try {
    await stopRecurrence.mutateAsync(stopAfter);
    toast.success("Recurrence stopped.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
</script>

<template>
  <AppModal :busy="del.isPending.value" :open="props.open" :title="props.commitment.title" size="lg" @close="emit('close')">
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div class="flex items-center gap-2">
          <StatusBadge :label="commitmentStatusLabel(props.commitment.activity_type, props.commitment.status)" :tone="statusTone(props.commitment.status)" />
          <span class="text-13 text-muted">{{ activityTypeLabel(props.commitment.activity_type) }}</span>
          <span class="text-13 text-muted">Category: {{ categoryLabel(props.commitment.kind) }}</span>
        </div>
        <div class="flex flex-wrap gap-2">
          <AppButton
            v-for="t in nextTransitions"
            :key="t.to"
            v-show="props.canEdit"
            variant="secondary"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="transition(t.to)"
          >
            {{ t.label }}
          </AppButton>
        </div>
      </div>

      <div class="grid sm:grid-cols-2 gap-x-6 gap-y-3 text-14">
        <div v-if="props.commitment.starts_at">
          <div class="text-13 text-muted">{{ dateStartLabel }}</div>
          <div>{{ props.commitment.is_all_day ? time.dateOnly(props.commitment.starts_at) : time.dateTime(props.commitment.starts_at) }}</div>
        </div>
        <div v-if="props.commitment.ends_at">
          <div class="text-13 text-muted">Ends</div>
          <div>{{ props.commitment.is_all_day ? time.dateOnly(props.commitment.ends_at) : time.dateTime(props.commitment.ends_at) }}</div>
        </div>
        <div v-if="hasLocation">
          <div class="text-13 text-muted">Location</div>
          <div v-if="props.commitment.location_label">{{ props.commitment.location_label }}</div>
          <div v-if="props.commitment.location_address" class="text-13 text-muted">{{ props.commitment.location_address }}</div>
        </div>
        <div v-if="props.commitment.owner_member_id">
          <div class="text-13 text-muted">Owner</div>
          <div>{{ memberName(props.commitment.owner_member_id) }}</div>
        </div>
        <div v-if="hasSupplierBooking">
          <div class="text-13 text-muted">{{ supplierLabel }}</div>
          <div v-if="props.commitment.supplier_name">{{ props.commitment.supplier_name }}</div>
          <div v-if="props.commitment.supplier_contact" class="text-13 text-muted">{{ props.commitment.supplier_contact }}</div>
          <div v-if="props.commitment.booking_reference" class="text-13 text-muted">
            {{ props.commitment.booking_reference }}
          </div>
          <StatusBadge v-if="workflow.preferredFields.booking && props.commitment.booking_confirmed" label="Confirmed" tone="accent" />
        </div>
        <div v-if="props.commitment.estimated_cost_minor != null">
          <div class="text-13 text-muted">Estimated cost</div>
          <div>{{ format(props.commitment.estimated_cost_minor, props.currency) }}</div>
        </div>
        <div v-if="isRecurring">
          <div class="text-13 text-muted">Repeats</div>
          <div>{{ repeatLabel }}</div>
          <div v-if="!props.commitment.recurrence_active && props.commitment.recurrence_end_date" class="text-13 text-muted">
            Stopped after {{ DateTime.fromISO(props.commitment.recurrence_end_date).toFormat("d LLL yyyy") }}
          </div>
        </div>
      </div>
      <p v-if="props.commitment.notes" class="text-14 text-ink-soft whitespace-pre-wrap">{{ props.commitment.notes }}</p>

      <div v-if="isRecurring" class="rounded-xl border border-line bg-surface p-4">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h3 class="text-13 font-semibold uppercase tracking-wide text-ink-soft">Recurring activity</h3>
            <p v-if="nextOccurrence" class="mt-1 text-14 text-ink-soft">
              Next occurrence: {{ DateTime.fromISO(nextOccurrence.occurrence_date).toFormat("d LLL yyyy") }}
            </p>
            <p v-else class="mt-1 text-14 text-muted">No upcoming occurrences in the current window.</p>
          </div>
          <div v-if="props.canEdit && nextOccurrence" class="flex flex-wrap gap-2">
            <AppButton
              variant="secondary"
              size="sm"
              :loading="completeOccurrence.isPending.value"
              @click="completeNextOccurrence"
            >
              Complete occurrence
            </AppButton>
            <AppButton
              variant="secondary"
              size="sm"
              :loading="skipOccurrence.isPending.value"
              @click="skipNextOccurrence"
            >
              Skip occurrence
            </AppButton>
          </div>
        </div>
        <div v-if="props.canEdit && props.commitment.recurrence_active" class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end">
          <label class="block">
            <span class="text-13 font-medium block mb-1.5 text-ink-soft">Stop after</span>
            <input
              v-model="stopAfterDate"
              type="date"
              class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line"
            />
          </label>
          <AppButton
            variant="secondary"
            size="sm"
            :loading="stopRecurrence.isPending.value"
            @click="stopSeries"
          >
            Stop recurrence
          </AppButton>
        </div>
      </div>

      <div>
        <h3 class="text-13 font-semibold text-ink-soft uppercase tracking-wide mb-2">Participants</h3>
        <div v-if="partPending" class="text-13 text-muted">Loading…</div>
        <div v-else class="flex flex-wrap gap-2 mb-2.5">
          <span v-if="participants.length === 0" class="text-13 text-muted">No one added yet.</span>
          <span
            v-for="p in participants"
            :key="p.id"
            class="inline-flex items-center gap-2 pl-1 pr-2 py-1 rounded-full border border-line bg-surface text-13"
          >
            <AppAvatar :name="memberName(p.member_id)" :size="20" />
            {{ memberName(p.member_id) }}
            <button v-if="props.canEdit" class="text-muted hover:text-danger" :disabled="removeParticipant.isPending.value" @click="doRemoveParticipant(p.id)">×</button>
          </span>
        </div>
        <div v-if="props.canEdit && addableMembers.length > 0" class="flex gap-2">
          <select v-model="selectedNewParticipant" class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface">
            <option value="">Add a participant…</option>
            <option v-for="m in addableMembers" :key="m.member_id" :value="m.member_id">{{ m.display_name }}</option>
          </select>
          <AppButton size="sm" variant="secondary" :disabled="!selectedNewParticipant" :loading="addParticipant.isPending.value" @click="submitAddParticipant">Add</AppButton>
        </div>
      </div>

      <PaymentsPanel
        v-if="showPayments"
        :project-id="props.projectId"
        :commitment-id="props.commitment.id"
        :currency="props.currency"
        :timezone="props.timezone"
        :can-edit="props.canEditPayments"
        :members="props.members"
      />
    </div>

    <!-- Keep confirmation inside the Dialog tree so Headless UI treats it as
         the active nested dialog (focus, inert handling and outside clicks). -->
    <AppConfirmDialog
      :open="confirmDelete"
      title="Delete activity"
      :message="`Delete '${props.commitment.title}'? This can't be undone from here.`"
      confirm-label="Delete"
      danger
      :loading="del.isPending.value"
      @close="confirmDelete = false"
      @confirm="doDelete"
    />

    <template #footer>
      <AppButton v-if="props.canDelete" variant="ghost" size="sm" class="!text-danger mr-auto" @click="confirmDelete = true">Delete</AppButton>
      <AppButton variant="secondary" size="sm" @click="emit('close')">Close</AppButton>
      <AppButton v-if="props.canEdit" size="sm" @click="emit('edit')">Edit</AppButton>
    </template>
  </AppModal>

</template>

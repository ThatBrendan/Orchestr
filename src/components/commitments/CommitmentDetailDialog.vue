<script setup lang="ts">
import { computed, ref } from "vue";
import { useSetCommitmentStatus, useDeleteCommitment, useParticipants, useAddParticipant, useRemoveParticipant } from "@/composables/useCommitments";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
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
const addParticipant = useAddParticipant(props.commitment.id);
const removeParticipant = useRemoveParticipant(props.commitment.id);

const TRANSITIONS: Record<CommitmentStatus, { to: CommitmentStatus; label: string }[]> = {
  idea: [
    { to: "researching", label: "Move to researching" },
    { to: "cancelled", label: "Cancel" },
  ],
  researching: [
    { to: "idea", label: "Back to idea" },
    { to: "confirmed", label: "Confirm" },
    { to: "cancelled", label: "Cancel" },
  ],
  confirmed: [
    { to: "researching", label: "Back to researching" },
    { to: "booked", label: "Mark booked" },
    { to: "cancelled", label: "Cancel" },
  ],
  booked: [
    { to: "confirmed", label: "Back to confirmed" },
    { to: "completed", label: "Mark completed" },
    { to: "cancelled", label: "Cancel" },
  ],
  completed: [{ to: "booked", label: "Reopen" }],
  cancelled: [{ to: "researching", label: "Reinstate" }],
};
const nextTransitions = computed(() => TRANSITIONS[props.commitment.status]);
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
  try {
    await del.mutateAsync(props.commitment.id);
    toast.success("Activity deleted.");
    confirmDelete.value = false;
    emit("close");
  } catch (e) {
    toast.error(toAppError(e).message);
    confirmDelete.value = false;
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
</script>

<template>
  <AppModal :open="props.open" :title="props.commitment.title" size="lg" @close="emit('close')">
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div class="flex items-center gap-2">
          <StatusBadge :label="props.commitment.status" :tone="statusTone(props.commitment.status)" />
          <span class="text-13 text-muted capitalize">{{ props.commitment.kind }}</span>
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
          <div class="text-13 text-muted">Starts</div>
          <div>{{ props.commitment.is_all_day ? time.dateOnly(props.commitment.starts_at) : time.dateTime(props.commitment.starts_at) }}</div>
        </div>
        <div v-if="props.commitment.ends_at">
          <div class="text-13 text-muted">Ends</div>
          <div>{{ props.commitment.is_all_day ? time.dateOnly(props.commitment.ends_at) : time.dateTime(props.commitment.ends_at) }}</div>
        </div>
        <div v-if="props.commitment.location_label || props.commitment.location_address">
          <div class="text-13 text-muted">Location</div>
          <div>{{ props.commitment.location_label }}</div>
          <div v-if="props.commitment.location_address" class="text-13 text-muted">{{ props.commitment.location_address }}</div>
        </div>
        <div v-if="props.commitment.owner_member_id">
          <div class="text-13 text-muted">Owner</div>
          <div>{{ memberName(props.commitment.owner_member_id) }}</div>
        </div>
        <div v-if="props.commitment.supplier_name">
          <div class="text-13 text-muted">Supplier</div>
          <div>{{ props.commitment.supplier_name }}</div>
          <div v-if="props.commitment.supplier_contact" class="text-13 text-muted">{{ props.commitment.supplier_contact }}</div>
        </div>
        <div v-if="props.commitment.booking_reference">
          <div class="text-13 text-muted">Booking reference</div>
          <div>{{ props.commitment.booking_reference }} <StatusBadge v-if="props.commitment.booking_confirmed" label="Confirmed" tone="accent" /></div>
        </div>
        <div v-if="props.commitment.estimated_cost_minor != null">
          <div class="text-13 text-muted">Estimated cost</div>
          <div>{{ format(props.commitment.estimated_cost_minor, props.currency) }}</div>
        </div>
      </div>
      <p v-if="props.commitment.notes" class="text-14 text-ink-soft whitespace-pre-wrap">{{ props.commitment.notes }}</p>

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
            <button v-if="props.canEdit" class="text-muted hover:text-danger" @click="doRemoveParticipant(p.id)">×</button>
          </span>
        </div>
        <div v-if="props.canEdit && addableMembers.length > 0" class="flex gap-2">
          <select v-model="selectedNewParticipant" class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface">
            <option value="">Add a participant…</option>
            <option v-for="m in addableMembers" :key="m.member_id" :value="m.member_id">{{ m.display_name }}</option>
          </select>
          <AppButton size="sm" variant="secondary" :disabled="!selectedNewParticipant" @click="submitAddParticipant">Add</AppButton>
        </div>
      </div>

      <PaymentsPanel
        :project-id="props.projectId"
        :commitment-id="props.commitment.id"
        :currency="props.currency"
        :timezone="props.timezone"
        :can-edit="props.canEditPayments"
        :members="props.members"
      />
    </div>

    <template #footer>
      <AppButton v-if="props.canDelete" variant="ghost" size="sm" class="!text-danger mr-auto" @click="confirmDelete = true">Delete</AppButton>
      <AppButton variant="secondary" size="sm" @click="emit('close')">Close</AppButton>
      <AppButton v-if="props.canEdit" size="sm" @click="emit('edit')">Edit</AppButton>
    </template>
  </AppModal>

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
</template>

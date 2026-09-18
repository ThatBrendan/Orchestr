<script setup lang="ts">
import MemberBalances from '@/components/budget/MemberBalances.vue';
import {useProjectContext} from '@/composables/useProjectContext';
import {useQueryClient} from '@tanstack/vue-query';
import {completeAssignedItem} from '@/services/items';
import {invalidatePlanning} from '@/composables/invalidation';
import CostSplitEditor from "./CostSplitEditor.vue";
import { useCostShares } from "@/composables/useCostShares";
import { usePayments } from "@/composables/usePayments";
import { computed, ref } from "vue";
import { DateTime } from "luxon";
import { useSetCommitmentStatus, useCommitmentFinancials, useDeleteCommitment } from "@/composables/useCommitments";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import { bookingStatusLabel, bookingStatusActions, secondaryActivityActions, activityTypeLabel, activityWorkflow, commitmentStatusActions, commitmentStatusLabel } from "@/lib/activityWorkflows";
import { categoryLabel } from "@/lib/commitmentCategories";
import { recurrenceLabel } from "@/lib/recurrence";
import type { Commitment } from "@/services/commitments";
import type { CommitmentStatus } from "@/types/database";
import type { MemberDirectoryEntry } from "@/types/derived";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import OccurrencePanel from "./OccurrencePanel.vue";
import PaymentsPanel from "./PaymentsPanel.vue";

const props = defineProps<{
  open: boolean;
  occurrenceDate?: string;
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
const {context,project}=useProjectContext(),client=useQueryClient();
const viewerCanComplete=computed(()=>context.value?.role==='viewer'&&context.value.memberId===props.commitment.owner_member_id&&project.value?.status!=='archived'&&!['completed','cancelled'].includes(props.commitment.status));
const viewerBusy=ref(false);
async function viewerComplete(){viewerBusy.value=true;try{await completeAssignedItem(props.commitment.id);await invalidatePlanning(client,props.projectId,[['project',props.projectId,'commitments']]);}catch(e){toast.error(toAppError(e).message);}finally{viewerBusy.value=false;}}

const setStatus = useSetCommitmentStatus(props.projectId);
const del = useDeleteCommitment(props.projectId);
const workflow = computed(() => activityWorkflow(props.commitment.activity_type));
const nextTransitions = computed(() => commitmentStatusActions(props.commitment.activity_type, props.commitment.status));
const bookingActions = computed(() => bookingStatusActions(props.commitment.status));
const secondaryActions = computed(() => secondaryActivityActions(props.commitment.activity_type, props.commitment.status));
const statusTone = (s: string) => (s === "cancelled" ? "neutral" : s === "completed" ? "success" : "amber");

const { financials, refetch: refetchFinancials } = useCommitmentFinancials(computed(() => props.commitment.id));
const shares = useCostShares(() => props.commitment.id);
const { payments } = usePayments(props.commitment.id);
const paymentsPanel = ref<InstanceType<typeof PaymentsPanel>>();
const outstandingOpen = ref(false);
const costBearing = computed(() => props.commitment.estimated_cost_minor != null || props.commitment.confirmed_cost_minor != null || props.commitment.actual_cost_minor != null || payments.value.length > 0);
const sharingConfigured = computed(() => ['even', 'custom'].includes(props.commitment.cost_split_mode ?? '') || (shares.data.value?.length ?? 0) > 0);
const cost = computed(() => props.commitment.actual_cost_minor ?? props.commitment.confirmed_cost_minor ?? props.commitment.estimated_cost_minor);
function recordOutstanding() {
  outstandingOpen.value = false;
  paymentsPanel.value?.openAdd();
}
async function transition(to: CommitmentStatus) {
  if (setStatus.isPending.value || !props.canEdit || isRecurring.value) return;
  try {
    await setStatus.mutateAsync({ id: props.commitment.id, status: to });
    toast.success("Status updated.");
  } catch (e) {
    if (toAppError(e).code === "financial_unsettled") {
      await refetchFinancials();
      outstandingOpen.value = true;
    } else toast.error(toAppError(e).message);
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
const showPayments = computed(() => costBearing.value);
const dateStartLabel = computed(() => (props.commitment.activity_type === "task" || props.commitment.activity_type === "purchase" ? "Due" : "Starts"));
const supplierLabel = computed(() => (workflow.value.preferredFields.booking ? "Supplier / booking" : "Supplier"));
const isRecurring = computed(() => props.commitment.recurrence_frequency != null);
const repeatLabel = computed(() =>
  recurrenceLabel(props.commitment.recurrence_frequency, props.commitment.recurrence_interval),
);
</script>

<template>
  <AppModal
    :busy="del.isPending.value"
    :open="props.open"
    :title="props.commitment.title"
    size="lg"
    @close="emit('close')"
  >
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div class="flex items-center gap-2">
          <StatusBadge
            :label="commitmentStatusLabel(props.commitment.activity_type, props.commitment.status)"
            :tone="statusTone(props.commitment.status)"
          />
          <span class="text-13 text-muted">{{ activityTypeLabel(props.commitment.activity_type) }}</span>
          <span class="text-13 text-muted">Category: {{ categoryLabel(props.commitment.kind) }}</span>
        </div>
        <AppButton
          v-if="viewerCanComplete && !isRecurring && nextTransitions.some(t=>t.to==='completed')"
          :loading="viewerBusy"
          @click="viewerComplete"
        >
          Complete
        </AppButton>
        <span
          v-else-if="props.commitment.status === 'completed'"
          class="inline-flex items-center gap-1 rounded px-2 py-1 bg-success-soft text-success text-[12.5px] font-medium"
        >
          <span aria-hidden="true">✓</span>
          Complete
        </span>
        <div
          v-if="props.canEdit && !isRecurring && props.commitment.status !== 'completed'"
          class="flex flex-wrap items-center gap-2"
        >
          <AppButton
            v-for="t in nextTransitions"
            :key="t.to"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="transition(t.to)"
          >
            {{ t.label }}
          </AppButton>
          <details class="text-13">
            <summary class="cursor-pointer focus-ring rounded px-2 py-1 text-muted">
              More
            </summary>
            <div class="flex flex-wrap gap-2 mt-2">
              <AppButton
                v-if="props.canDelete"
                variant="ghost"
                size="sm"
                class="!text-danger"
                @click="confirmDelete = true"
              >
                Delete activity
              </AppButton>
              <AppButton
                v-for="t in secondaryActions"
                :key="t.to"
                variant="ghost"
                size="sm"
                :loading="setStatus.isPending.value"
                @click="transition(t.to)"
              >
                {{ t.label }}
              </AppButton>
            </div>
          </details>
        </div>
      </div>
      <section
        v-if="props.commitment.activity_type === 'booking'"
        class="rounded-xl border border-line p-4"
        aria-label="Booking status"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p class="text-13 text-muted mb-1">
              Booking
            </p><StatusBadge
              :label="bookingStatusLabel(props.commitment.status, props.commitment.booking_confirmed)"
              tone="neutral"
            />
          </div>
          <div
            v-if="props.canEdit && !isRecurring"
            class="flex flex-wrap gap-2"
          >
            <AppButton
              v-for="t in bookingActions"
              :key="t.to"
              variant="secondary"
              size="sm"
              :loading="setStatus.isPending.value"
              @click="transition(t.to)"
            >
              {{ t.label }}
            </AppButton>
          </div>
        </div>
        <p
          v-if="!isRecurring && ['idea', 'researching', 'confirmed'].includes(props.commitment.status)"
          class="text-13 text-muted mt-3"
        >
          {{ props.commitment.status === 'idea' ? 'Start the activity, then record its booking here.' : 'Finish the booking steps here before completing the activity.' }} Booking and execution are tracked separately.
        </p>
      </section>

      <div class="grid sm:grid-cols-2 gap-x-6 gap-y-3 text-14">
        <div v-if="props.commitment.starts_at">
          <div class="text-13 text-muted">
            {{ dateStartLabel }}
          </div>
          <div>{{ props.commitment.is_all_day ? time.dateOnly(props.commitment.starts_at) : time.dateTime(props.commitment.starts_at) }}</div>
        </div>
        <div v-if="props.commitment.ends_at">
          <div class="text-13 text-muted">
            Ends
          </div>
          <div>{{ props.commitment.is_all_day ? time.dateOnly(props.commitment.ends_at) : time.dateTime(props.commitment.ends_at) }}</div>
        </div>
        <div v-if="hasLocation">
          <div class="text-13 text-muted">
            Location
          </div>
          <div v-if="props.commitment.location_label">
            {{ props.commitment.location_label }}
          </div>
          <div
            v-if="props.commitment.location_address"
            class="text-13 text-muted"
          >
            {{ props.commitment.location_address }}
          </div>
        </div>
        <div v-if="props.commitment.owner_member_id">
          <div class="text-13 text-muted">
            Assigned to
          </div>
          <div>{{ memberName(props.commitment.owner_member_id) }}</div>
        </div>
        <div v-if="hasSupplierBooking">
          <div class="text-13 text-muted">
            {{ supplierLabel }}
          </div>
          <div v-if="props.commitment.supplier_name">
            {{ props.commitment.supplier_name }}
          </div>
          <div
            v-if="props.commitment.supplier_contact"
            class="text-13 text-muted"
          >
            {{ props.commitment.supplier_contact }}
          </div>
          <div
            v-if="props.commitment.booking_reference"
            class="text-13 text-muted"
          >
            {{ props.commitment.booking_reference }}
          </div>
        </div>
        <div v-if="isRecurring">
          <div class="text-13 text-muted">
            Repeats
          </div>
          <div>{{ repeatLabel }}</div>
          <div
            v-if="!props.commitment.recurrence_active && props.commitment.recurrence_end_date"
            class="text-13 text-muted"
          >
            Stopped after {{ DateTime.fromISO(props.commitment.recurrence_end_date).toFormat("d LLL yyyy") }}
          </div>
        </div>
      </div>
      <section
        v-if="costBearing"
        class="grid grid-cols-1 sm:grid-cols-3 gap-3 rounded-xl border border-line p-4 text-14"
      >
        <div>
          <p class="text-muted text-13">
            Cost
          </p>{{ format(cost, props.currency) }}
        </div>
        <div>
          <p class="text-muted text-13">
            Paid
          </p>{{ format(financials?.net_paid_minor, props.currency) }}
        </div>
        <div>
          <p class="text-muted text-13">
            Remaining
          </p>{{ format(financials?.outstanding_minor, props.currency) }}
        </div>
      </section>
      <div v-if="props.commitment.notes">
        <h3 class="text-13 font-medium mb-2">
          {{ isRecurring ? 'Instructions' : 'Notes' }}
        </h3>
        <p class="text-14 text-ink-soft whitespace-pre-wrap [overflow-wrap:anywhere]">
          {{ props.commitment.notes }}
        </p>
      </div>
      <OccurrencePanel
        v-if="isRecurring"
        :project-id="props.projectId"
        :commitment-id="props.commitment.id"
        :timezone="props.timezone"
        :occurrence-date="props.occurrenceDate"
        :can-edit="props.canEdit"
        :can-complete-assigned="viewerCanComplete"
        :recurrence-active="props.commitment.recurrence_active"
      />

      <PaymentsPanel
        v-if="showPayments"
        ref="paymentsPanel"
        :project-id="props.projectId"
        :commitment-id="props.commitment.id"
        :currency="props.currency"
        :timezone="props.timezone"
        :can-edit="props.canEditPayments"
        :members="props.members"
      />
    </div>

    <CostSplitEditor
      v-if="open && costBearing && sharingConfigured && members.filter(m=>m.status==='active').length > 1"
      :key="props.commitment.id + String(props.commitment.cost_split_mode)"
      :commitment="props.commitment"
      :cost="props.commitment.actual_cost_minor ?? props.commitment.confirmed_cost_minor ?? props.commitment.estimated_cost_minor"
      :currency="props.currency"
      :members="props.members"
      readonly
    />
    <MemberBalances
      v-if="costBearing && sharingConfigured && members.filter(m=>m.status==='active').length > 1"
      :key="props.commitment.id"
      :item-id="props.commitment.id"
      :project-id="props.projectId"
      :currency="props.currency"
      :timezone="props.timezone"
      :can-edit="props.canEditPayments"
    />
    <AppConfirmDialog
      :open="outstandingOpen"
      title="Payment outstanding"
      :message="financials && financials.outstanding_minor > 0 ? format(financials.outstanding_minor, currency) + ' is still outstanding. This activity can’t be completed until the outstanding payment is recorded.' : 'This activity still has scheduled payments or member shares to settle. Review its payments before completing it.'"
      :confirm-label="canEditPayments ? 'Record payment' : 'Close'"
      @close="outstandingOpen = false"
      @confirm="canEditPayments ? recordOutstanding() : outstandingOpen = false"
    />
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
      <AppButton
        variant="secondary"
        size="sm"
        @click="emit('close')"
      >
        Close
      </AppButton>
      <AppButton
        v-if="props.canEdit"
        size="sm"
        @click="emit('edit')"
      >
        Edit
      </AppButton>
    </template>
  </AppModal>
</template>

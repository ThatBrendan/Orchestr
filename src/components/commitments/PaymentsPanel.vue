<script setup lang="ts">
import {useProjectContext} from '@/composables/useProjectContext';
import { computed, reactive, ref, watch } from "vue";
import { DateTime } from "luxon";
import { usePayments, useCreatePayment, useMarkPaymentPaid, useSetPaymentStatus } from "@/composables/usePayments";
import { useCommitmentFinancials } from "@/composables/useCommitments";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import type { MemberDirectoryEntry } from "@/types/derived";
import type { Enums } from "@/types/database";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { presentLabel } from "@/lib/presentation";

const props = defineProps<{
  projectId: string;
  commitmentId: string;
  currency: string;
  timezone: string;
  canEdit: boolean;
  members: MemberDirectoryEntry[];
}>();

const { payments: allPayments, isPending, isError, error, refetch } = usePayments(props.commitmentId);
const payments=computed(()=>allPayments.value.filter(p=>!p.settlement_group_id));
const {context,isOrganizer}=useProjectContext();
const payers=computed(()=>props.members.filter(m=>m.status==='active'&&(isOrganizer.value||m.member_id===context.value?.memberId)));
const { financials } = useCommitmentFinancials(props.commitmentId);
const { format, toMinor, toMajor } = useMoney();
const time = useProjectTime(props.timezone);
const toast = useToast();

const createPayment = useCreatePayment(props.projectId, props.commitmentId);
const markPaid = useMarkPaymentPaid(props.projectId, props.commitmentId);
const setStatus = useSetPaymentStatus(props.projectId, props.commitmentId);

const TYPES: Enums<"payment_type">[] = ["deposit", "full", "balance"];
const mode = ref<"paid" | "refund" | "scheduled">("paid");
const today = () => DateTime.now().setZone(props.timezone).toISODate() ?? "";

const showAddForm = ref(false);
const addForm = reactive({
  paid_by_member_id: "",
  type: "deposit" as Enums<"payment_type">,
  amount_major: "",
  due_on: today(),
});
const addError = ref<string | null>(null);
function openAdd(nextMode: "paid" | "refund" | "scheduled" = "paid") {
  mode.value = nextMode;
  addForm.paid_by_member_id=context.value?.memberId??"";
  addForm.type = "deposit";
  addForm.amount_major = "";
  addForm.due_on = today();
  addError.value = null;
  showAddForm.value = true;
}
defineExpose({ openAdd });
watch(() => addForm.type, type => {
  if (mode.value !== "refund" && (type === "full" || type === "balance") && financials.value) {
    addForm.amount_major = String(toMajor(financials.value.outstanding_minor, props.currency) ?? "");
  }
});
const addLabel = computed(() => mode.value === "refund" ? "Record refund" : mode.value === "scheduled" ? "Schedule payment" : "Add payment");

async function submitAdd() {
  if (createPayment.isPending.value || !props.canEdit) return;
  addError.value = null;
  if (!addForm.due_on || (mode.value !== "scheduled" && addForm.due_on > today())) {
    addError.value = "Choose the date this payment happened, today or earlier.";
    return;
  }
  let amountMinor: number | null;
  try { amountMinor = toMinor(addForm.amount_major, props.currency); }
  catch (error) { addError.value = toAppError(error).message; return; }
  if (amountMinor == null || amountMinor <= 0) {
    addError.value = "Enter an amount greater than zero.";
    return;
  }
  try {
    await createPayment.mutateAsync({
      project_id: props.projectId,
      commitment_id: props.commitmentId,
      type: mode.value === "refund" ? "refund" : addForm.type,
      direction: mode.value === "refund" ? "incoming" : "outgoing",
      status: mode.value === "scheduled" ? "scheduled" : "paid",
      paid_on: mode.value === "scheduled" ? null : addForm.due_on,
      amount_minor: amountMinor,
      paid_by_member_id:addForm.paid_by_member_id||null,
      due_on: mode.value === "scheduled" ? addForm.due_on : null,
    });
    toast.success(mode.value === "scheduled" ? "Payment scheduled." : "Payment recorded.");
    addForm.amount_major = "";
    addForm.due_on = "";
    showAddForm.value = false;
  } catch (e) {
    addError.value = toAppError(e).message;
  }
}

const markPaidRowId = ref<string | null>(null);
const markPaidForm = reactive({ paid_on: DateTime.now().toISODate() as string, paid_by_member_id: "", method: "", reference: "" });
const markPaidError = ref<string | null>(null);

function openMarkPaid(id: string) {
  markPaidRowId.value = id;
  markPaidForm.paid_on = DateTime.now().setZone(props.timezone).toISODate() as string;
  markPaidForm.paid_by_member_id = "";
  markPaidForm.method = "";
  markPaidForm.reference = "";
  markPaidError.value = null;
}

async function submitMarkPaid() {
  if (!markPaidRowId.value || markPaid.isPending.value) return;
  markPaidError.value = null;
  try {
    await markPaid.mutateAsync({
      id: markPaidRowId.value,
      paid_on: markPaidForm.paid_on,
      paid_by_member_id: markPaidForm.paid_by_member_id || null,
      method: markPaidForm.method.trim() || null,
      reference: markPaidForm.reference.trim() || null,
    });
    toast.success("Payment marked as paid.");
    markPaidRowId.value = null;
  } catch (e) {
    markPaidError.value = toAppError(e).message;
  }
}

async function cancelPayment(id: string) {
  if (setStatus.isPending.value) return;
  try {
    await setStatus.mutateAsync({ id, status: "cancelled" });
    toast.success("Payment cancelled.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

const statusTone = (s: string) => (s === "paid" ? "success" : s === "cancelled" ? "neutral" : s === "waived" ? "neutral" : "amber");

</script>

<template>
  <div>
    <div class="flex items-center justify-between mb-3">
      <div>
        <h3 class="text-13 font-semibold text-ink-soft uppercase tracking-wide">
          Payments
        </h3>
      </div>
      <AppButton
        v-if="props.canEdit"
        variant="secondary"
        size="sm"
        @click="showAddForm ? showAddForm = false : openAdd()"
      >
        {{ showAddForm ? "Cancel" : "Add payment" }}
      </AppButton>
    </div>

    <details
      v-if="props.canEdit"
      class="mb-3 text-13"
    >
      <summary class="cursor-pointer focus-ring">
        More payment options
      </summary>
      <div class="flex flex-wrap gap-2 mt-2">
        <AppButton
          variant="ghost"
          size="sm"
          @click="openAdd('refund')"
        >
          Record refund
        </AppButton>
        <AppButton
          variant="ghost"
          size="sm"
          @click="openAdd('scheduled')"
        >
          Schedule payment
        </AppButton>
      </div>
    </details>
    <form
      v-if="showAddForm"
      class="border rounded-lg p-3.5 mb-3 space-y-3 border-line bg-[#FBFBFA]"
      @submit.prevent="submitAdd"
    >
      <label
        v-if="payers.length"
        class="block text-13"
      >{{ mode==='refund'?'Refund received by':'Paid by' }}<select
        v-model="addForm.paid_by_member_id"
        class="block w-full mt-1 border border-line rounded-lg p-2 bg-surface"
      ><option value="">Unattributed</option><option
        v-for="member in payers"
        :key="member.member_id"
        :value="member.member_id"
      >{{ member.display_name }}</option></select></label>
      <div class="grid sm:grid-cols-2 gap-2">
        <select
          v-if="mode !== 'refund'"
          v-model="addForm.type"
          aria-label="Payment type"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
        >
          <option
            v-for="t in TYPES"
            :key="t"
            :value="t"
          >
            {{ t === "full" ? "Full payment" : presentLabel(t) }}
          </option>
        </select>
        <input
          v-model="addForm.due_on"
          aria-label="Date"
          :max="mode === 'scheduled' ? undefined : today()"
          required
          type="date"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line"
        >
      </div>
      <input
        v-model="addForm.amount_major"
        aria-label="Amount"
        type="text"
        inputmode="decimal"
        :placeholder="`Amount (${props.currency})`"
        class="w-full border rounded-lg px-3 py-2 text-13.5 focus-ring border-line"
      >
      <p
        v-if="addError"
        class="text-13 text-danger"
      >
        {{ addError }}
      </p>
      <AppButton
        size="sm"
        :loading="createPayment.isPending.value"
        @click="submitAdd"
      >
        {{ addLabel }}
      </AppButton>
    </form>

    <div
      v-if="isPending"
      class="space-y-2"
    >
      <SkeletonBlock
        v-for="i in 2"
        :key="i"
        height="44px"
        rounded="0.5rem"
      />
    </div>
    <ErrorState
      v-else-if="isError"
      :error="error"
      :retry="() => refetch()"
    />
    <EmptyState
      v-else-if="payments.length === 0"
      message="No payments recorded for this activity yet."
    />
    <div
      v-else
      class="border rounded-lg divide-y border-line"
    >
      <div
        v-for="p in payments"
        :key="p.id"
        class="px-3 py-2.5"
      >
        <div class="flex flex-wrap items-center gap-2.5">
          <StatusBadge
            :label="presentLabel(p.status)"
            :tone="statusTone(p.status)"
          />
          <span class="text-13.5">{{ presentLabel(p.type) }}</span>
          <span class="max-w-full [overflow-wrap:anywhere] text-13.5 font-medium sm:ml-auto">{{ format(p.amount_minor, props.currency) }}</span>
        </div>
        <div class="text-13 text-muted mt-1">
          <span v-if="p.due_on">Due {{ time.dateOnly(p.due_on) }}</span>
          <span v-if="p.paid_on"> · Paid {{ time.dateOnly(p.paid_on) }}</span>
        </div>

        <div
          v-if="props.canEdit && p.status === 'scheduled'"
          class="mt-2 flex flex-wrap gap-2"
        >
          <AppButton
            variant="secondary"
            size="sm"
            @click="openMarkPaid(p.id)"
          >
            Mark paid
          </AppButton>
          <AppButton
            variant="ghost"
            size="sm"
            :loading="setStatus.isPending.value"
            @click="cancelPayment(p.id)"
          >
            Cancel
          </AppButton>
        </div>

        <form
          v-if="markPaidRowId === p.id"
          class="mt-2.5 border rounded-lg p-3 space-y-2 border-line bg-[#FBFBFA]"
          @submit.prevent="submitMarkPaid"
        >
          <div class="grid grid-cols-2 gap-2">
            <input
              v-model="markPaidForm.paid_on"
              type="date"
              class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line"
            >
            <select
              v-model="markPaidForm.paid_by_member_id"
              class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
            >
              <option value="">
                Paid by (optional)
              </option>
              <option
                v-for="m in props.members"
                :key="m.member_id"
                :value="m.member_id"
              >
                {{ m.display_name }}
              </option>
            </select>
          </div>
          <input
            v-model="markPaidForm.method"
            placeholder="Method (optional)"
            class="w-full border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line"
          >
          <p
            v-if="markPaidError"
            class="text-13 text-danger"
          >
            {{ markPaidError }}
          </p>
          <div class="flex gap-2">
            <AppButton
              size="sm"
              :loading="markPaid.isPending.value"
              @click="submitMarkPaid"
            >
              Confirm paid
            </AppButton>
            <AppButton
              variant="secondary"
              size="sm"
              @click="markPaidRowId = null"
            >
              Cancel
            </AppButton>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

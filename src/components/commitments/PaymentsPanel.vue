<script setup lang="ts">
import { computed, reactive, ref } from "vue";
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

const props = defineProps<{
  projectId: string;
  commitmentId: string;
  currency: string;
  timezone: string;
  canEdit: boolean;
  members: MemberDirectoryEntry[];
}>();

const { payments, isPending, isError, error, refetch } = usePayments(props.commitmentId);
const { financials } = useCommitmentFinancials(props.commitmentId);
const { format, toMinor } = useMoney();
const time = useProjectTime(props.timezone);
const toast = useToast();

const createPayment = useCreatePayment(props.projectId, props.commitmentId);
const markPaid = useMarkPaymentPaid(props.projectId, props.commitmentId);
const setStatus = useSetPaymentStatus(props.projectId, props.commitmentId);

const TYPES: Enums<"payment_type">[] = ["deposit", "balance", "installment", "full", "refund"];

const showAddForm = ref(false);
const addForm = reactive({
  type: "deposit" as Enums<"payment_type">,
  direction: "outgoing" as Enums<"payment_direction">,
  amount_major: "",
  due_on: "",
});
const addError = ref<string | null>(null);

async function submitAdd() {
  if (createPayment.isPending.value || !props.canEdit) return;
  addError.value = null;
  const amountMinor = toMinor(addForm.amount_major, props.currency);
  if (amountMinor == null || amountMinor <= 0) {
    addError.value = "Enter an amount greater than zero.";
    return;
  }
  try {
    await createPayment.mutateAsync({
      project_id: props.projectId,
      commitment_id: props.commitmentId,
      type: addForm.type,
      direction: addForm.type === "refund" ? "incoming" : addForm.direction,
      amount_minor: amountMinor,
      due_on: addForm.due_on || null,
    });
    toast.success("Payment scheduled.");
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

const statusTone = (s: string) => (s === "paid" ? "accent" : s === "cancelled" ? "neutral" : s === "waived" ? "neutral" : "amber");
const outstanding = computed(() => financials.value?.outstanding_minor ?? null);
</script>

<template>
  <div>
    <div class="flex items-center justify-between mb-3">
      <div>
        <h3 class="text-13 font-semibold text-ink-soft uppercase tracking-wide">
          Payments
        </h3>
        <p class="text-13 text-muted mt-0.5">
          Outstanding: <span class="font-medium text-ink">{{ outstanding != null ? format(outstanding, props.currency) : "—" }}</span>
        </p>
      </div>
      <AppButton
        v-if="props.canEdit"
        variant="secondary"
        size="sm"
        @click="showAddForm = !showAddForm"
      >
        {{ showAddForm ? "Cancel" : "Add payment" }}
      </AppButton>
    </div>

    <form
      v-if="showAddForm"
      class="border rounded-lg p-3.5 mb-3 space-y-3 border-line bg-[#FBFBFA]"
      @submit.prevent="submitAdd"
    >
      <div class="grid grid-cols-3 gap-2">
        <select
          v-model="addForm.type"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
        >
          <option
            v-for="t in TYPES"
            :key="t"
            :value="t"
          >
            {{ t }}
          </option>
        </select>
        <select
          v-model="addForm.direction"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
        >
          <option value="outgoing">
            Outgoing
          </option>
          <option value="incoming">
            Incoming
          </option>
        </select>
        <input
          v-model="addForm.due_on"
          type="date"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line"
        >
      </div>
      <input
        v-model="addForm.amount_major"
        type="number"
        step="0.01"
        min="0.01"
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
        Schedule payment
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
        <div class="flex items-center gap-2.5">
          <StatusBadge
            :label="p.status"
            :tone="statusTone(p.status)"
          />
          <span class="text-13.5 capitalize">{{ p.type }}</span>
          <span class="text-13.5 font-medium ml-auto">{{ format(p.amount_minor, props.currency) }}</span>
        </div>
        <div class="text-13 text-muted mt-1">
          <span v-if="p.due_on">Due {{ time.dateOnly(p.due_on) }}</span>
          <span v-if="p.paid_on"> · Paid {{ time.dateOnly(p.paid_on) }}</span>
        </div>

        <div
          v-if="props.canEdit && p.status === 'scheduled'"
          class="mt-2 flex gap-2"
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

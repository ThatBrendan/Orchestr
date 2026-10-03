<script setup lang="ts">
import { computed, nextTick, ref } from 'vue';
import { DialogDescription } from '@headlessui/vue';
import { useProjectContext } from '@/composables/useProjectContext';
import { useMoney } from '@/composables/useMoney';
import { usePaymentStatus, useRefreshPaymentStatus } from '@/composables/usePaymentAcknowledgements';
import { acknowledgePayment, withdrawPayment } from '@/services/paymentAcknowledgements';
import { toAppError } from '@/lib/errors';
import type { Reimbursement } from '@/types/reimbursements';
import AppButton from '@/components/ui/AppButton.vue';
import AppModal from '@/components/ui/AppModal.vue';
import StatusBadge from '@/components/ui/StatusBadge.vue';
import ReimbursementPaymentOptions from './ReimbursementPaymentOptions.vue';
const props = defineProps<{ r: Reimbursement }>();
const emit = defineEmits<{ cancel: [request: Reimbursement, acknowledged: boolean] }>();
const { project } = useProjectContext();
const { format } = useMoney();
const status = usePaymentStatus(() => props.r.id);
const refresh = useRefreshPaymentStatus(props.r.project_id);
const active = computed(() => status.data.value?.active_acknowledgement_id);
const cardElement = ref<HTMLElement | null>(null);
let opener: HTMLElement | null = null;
function showConfirmation(kind: 'acknowledge' | 'withdraw', event: MouseEvent) {
  opener = event.currentTarget as HTMLElement;
  undoTarget.value = active.value ?? null;
  modal.value = kind; error.value = '';
}
async function restoreFocus() {
  await nextTick();
  requestAnimationFrame(() => (opener?.isConnected ? opener : cardElement.value)?.focus());
}
const undoTarget = ref<string | null>(null);
const actionable = computed(() => props.r.status === 'open' && !props.r.needs_review && project.value?.status !== 'archived');
const modal = ref<'acknowledge' | 'withdraw' | null>(null), busy = ref(false), error = ref('');
function perspective(r: Reimbursement) { return r.is_debtor ? `You owe ${r.creditor_name}` : r.is_creditor ? `${r.debtor_name} owes you` : `${r.debtor_name} owes ${r.creditor_name}`; }
async function confirm() {
  if (busy.value || !modal.value) return;
  busy.value = true; error.value = '';
  try {
    if (modal.value === 'acknowledge') await acknowledgePayment(props.r.id);
    else if (undoTarget.value) await withdrawPayment(undoTarget.value);
    modal.value = null;
  } catch (e) { error.value = toAppError(e).message; }
  finally { await refresh(); busy.value = false; }
}
</script>
<template>
  <div
    ref="cardElement"
    tabindex="-1"
    class="rounded-lg border border-line p-3 space-y-2 text-13"
    :data-reimbursement-id="r.id"
  >
    <p class="font-medium">
      {{ r.status === 'cancelled' || r.needs_review ? `${r.debtor_name} → ${r.creditor_name}` : perspective(r) }}
    </p>
    <div class="flex flex-wrap items-center gap-2">
      <span>{{ r.needs_review ? 'Original request: ' : '' }}{{ format(r.amount_minor, r.currency) }}</span>
      <StatusBadge
        :label="r.status === 'cancelled' ? 'Cancelled' : r.needs_review ? 'Review needed' : status.isError.value ? 'Status unavailable' : status.isPending.value ? 'Checking payment status' : active ? 'Payment sent' : 'Outstanding'"
        tone="neutral"
      />
    </div>
    <p v-if="r.needs_review">
      Payments or shares changed. This original request needs review; cancel and recreate it using the current balances.
    </p>
    <p class="text-muted">
      {{ r.activity_title }} · From {{ format(r.source_amount_minor, r.currency) }} paid by {{ r.creditor_name }} on {{ r.source_paid_on }} · Request created {{ new Date(r.created_at).toLocaleDateString() }}
    </p>
    <p
      v-if="status.isError.value"
      role="status"
    >
      Payment status unavailable. <button
        class="underline"
        @click="status.refetch()"
      >
        Retry
      </button>
    </p>
    <p
      v-else-if="status.isPending.value"
      role="status"
    >
      Loading payment status…
    </p>
    <template v-else>
      <p v-if="active && (r.needs_review || r.status==='cancelled')">
        Payment was previously marked as sent. No settlement has been recorded.
      </p>
      <p
        v-else-if="active"
        role="status"
      >
        {{ r.is_creditor ? r.debtor_name+" says they've paid. Awaiting your confirmation." : 'Awaiting '+r.creditor_name+"'s confirmation." }} This has not been recorded as settled.
      </p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          v-if="actionable && status.data.value?.can_acknowledge"
          size="sm"
          @click="showConfirmation('acknowledge', $event)"
        >
          I've paid
        </AppButton>
        <AppButton
          v-if="actionable && status.data.value?.can_withdraw"
          size="sm"
          variant="ghost"
          @click="showConfirmation('withdraw', $event)"
        >
          Undo payment sent
        </AppButton>
      </div>
    </template>
    <ReimbursementPaymentOptions
      v-if="status.isSuccess.value && !status.isError.value && !active && r.is_debtor && r.status==='open' && !r.needs_review && project?.status!=='archived'"
      :request-id="r.id"
      :creditor-name="r.creditor_name"
    />
    <p
      v-if="r.is_debtor && r.needs_review"
      class="text-muted"
    >
      This reimbursement needs review before payment.
    </p>
    <AppButton
      v-if="r.can_cancel"
      size="sm"
      variant="ghost"
      @click="emit('cancel', r, !!active)"
    >
      Cancel reimbursement
    </AppButton>
    <details
      v-if="status.data.value?.history.length"
      class="text-muted"
    >
      <summary class="cursor-pointer focus-ring">
        Payment-sent history
      </summary>
      <ul class="mt-2 space-y-2">
        <li
          v-for="entry in status.data.value.history"
          :key="entry.id"
        >
          Marked as sent {{ new Date(entry.acknowledged_at).toLocaleString() }}.
          <span v-if="entry.withdrawn_at">Withdrawn {{ new Date(entry.withdrawn_at).toLocaleString() }}.</span>
        </li>
      </ul>
    </details>
  </div>
  <AppModal
    :open="!!modal"
    :title="modal==='withdraw' ? 'Undo payment sent?' : 'Mark payment as sent?'"
    :busy="busy"
    @close="modal=null"
    @after-close="restoreFocus"
  >
    <DialogDescription>
      {{ modal==='withdraw' ? r.creditor_name+' will see that this payment is no longer marked as sent.' : "This tells "+r.creditor_name+" you've sent the full "+format(r.amount_minor,r.currency)+". It won't be recorded as settled until they confirm receipt." }}
    </DialogDescription>
    <p
      v-if="error"
      role="alert"
      class="mt-3 text-danger"
    >
      {{ error }}
    </p>
    <template #footer>
      <AppButton
        variant="ghost"
        :disabled="busy"
        @click="modal=null"
      >
        Go back
      </AppButton>
      <AppButton
        :loading="busy"
        @click="confirm"
      >
        {{ modal==='withdraw' ? 'Yes, undo' : "Yes, I've paid" }}
      </AppButton>
    </template>
  </AppModal>
</template>

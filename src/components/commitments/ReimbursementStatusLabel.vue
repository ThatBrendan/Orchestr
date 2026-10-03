<script setup lang="ts">
import { usePaymentStatus } from '@/composables/usePaymentAcknowledgements';
import type { Reimbursement } from '@/types/reimbursements';
const props = defineProps<{ request: Reimbursement }>();
const status = usePaymentStatus(() => props.request.id);
</script>
<template>
  <span class="block text-muted">{{ request.status==='cancelled' ? 'Cancelled' : request.needs_review ? 'Review needed — original request amount' : status.isError.value ? 'Payment status unavailable.' : status.isPending.value ? 'Loading payment status…' : status.data.value?.confirmation_state === 'reversed' ? 'Settlement reversed' : request.status==='settled' ? 'Settled' : status.data.value?.active_acknowledgement_id ? 'Payment sent — awaiting confirmation' : 'Outstanding' }}</span>
</template>

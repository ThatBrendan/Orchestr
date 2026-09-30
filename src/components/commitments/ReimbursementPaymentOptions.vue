<script setup lang="ts">
import { useReimbursementPaymentOptions } from '@/composables/usePaymentLinks';
const props = defineProps<{ requestId: string; creditorName: string }>();
const query = useReimbursementPaymentOptions(() => props.requestId);
</script>
<template>
  <section
    class="space-y-2 border-t border-line pt-3"
    aria-label="Payment options"
  >
    <p
      v-if="query.isPending.value"
      class="text-muted"
    >
      Loading payment links…
    </p>
    <p v-else-if="query.isError.value">
      Payment link unavailable. <button
        class="underline focus-ring"
        @click="query.refetch()"
      >
        Retry
      </button>
    </p>
    <template v-else-if="query.data.value?.length">
      <h4 class="font-medium">
        Pay {{ creditorName }}
      </h4>
      <div
        v-for="option in query.data.value"
        :key="option.id"
        class="flex flex-wrap items-center justify-between gap-2"
        :data-payment-option-id="option.id"
      >
        <span class="min-w-0 [overflow-wrap:anywhere]">{{ option.display_label }}{{ option.is_default ? ' · Default' : '' }}</span>
        <a
          :href="option.payment_url"
          target="_blank"
          rel="noopener noreferrer"
          referrerpolicy="no-referrer"
          class="inline-flex min-h-11 items-center rounded-lg border border-line px-3 py-2 underline focus-ring"
          :aria-label="`Open ${option.display_label} payment link (opens in a new tab)`"
        >Open payment link <span class="sr-only">(opens in a new tab)</span></a>
      </div>
      <p class="text-muted">
        Payment happens outside Orchestrio. Opening a link does not mark this reimbursement as paid.
      </p>
    </template>
    <p
      v-else
      class="text-muted"
    >
      {{ creditorName }} has no payment link available for this reimbursement.
    </p>
  </section>
</template>

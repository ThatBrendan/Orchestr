<script setup lang="ts">
import { reactive, ref } from 'vue';
import AppButton from '@/components/ui/AppButton.vue';
import { usePaymentLinks } from '@/composables/usePaymentLinks';
import { paymentProviders, normalizePaymentUrl } from '@/lib/paymentProviders';
import { toAppError } from '@/lib/errors';
import * as service from '@/services/paymentLinks';
import type { PaymentLink, PaymentProvider } from '@/types/paymentLinks';
const { query, refresh } = usePaymentLinks();
const show = ref(false), busy = ref(false), error = ref(''), removing = ref<PaymentLink | null>(null);
const form = reactive({ id: undefined as string | undefined, provider: 'monzo' as PaymentProvider, url: '', label: '', enabled: true });
function edit(link?: PaymentLink) {
  Object.assign(form, { id: link?.id, provider: link?.provider ?? 'monzo', url: link?.payment_url ?? '', label: link?.display_label ?? '', enabled: link?.is_enabled ?? true });
  error.value = ''; show.value = true; removing.value = null;
}
async function mutate(action: () => Promise<unknown>) {
  if (busy.value) return;
  busy.value = true; error.value = '';
  try { await action(); await refresh(); show.value = false; removing.value = null; }
  catch (e) { error.value = e instanceof Error ? e.message : toAppError(e).message; }
  finally { busy.value = false; }
}
function save() {
  return mutate(async () => {
    const url = normalizePaymentUrl(form.provider, form.url);
    if (form.provider === 'custom' && (!form.label.trim() || form.label.trim().length > 60)) throw new Error('Enter a label of 1 to 60 characters.');
    await service.saveMyPaymentLink({ ...form, url });
  });
}
</script>
<template>
  <section
    id="payment-links-settings"
    class="mt-8 min-w-0 border-t border-line pt-6 space-y-4 [overflow-wrap:anywhere]"
    aria-labelledby="payment-links-title"
  >
    <h2
      id="payment-links-title"
      class="text-section-heading font-semibold"
    >
      My payment preferences
    </h2>
    <p class="text-meta text-muted">
      Add multiple payment preferences so people can choose how to reimburse you. Only people with an eligible reimbursement to pay you can see them. For Starling Settle Up, choose Other / Custom.
    </p>
    <p
      v-if="query.isPending.value"
      role="status"
    >
      Loading payment links…
    </p>
    <p
      v-else-if="query.isError.value"
      role="alert"
    >
      Could not load payment links. <button
        class="inline-flex min-h-11 items-center rounded-lg underline focus-ring"
        @click="query.refetch()"
      >
        Retry
      </button>
    </p>
    <p
      v-else-if="!query.data.value?.length"
      class="text-sm"
    >
      No payment links added.
    </p>
    <article
      v-for="link in query.data.value"
      :key="link.id"
      :data-payment-link-id="link.id"
      class="border-b border-line pb-4 space-y-2 min-w-0"
    >
      <p class="font-medium">
        {{ link.display_label }} <span
          v-if="link.is_default"
          class="text-meta text-muted"
        >· Default</span><span
          class="text-meta text-muted"
        >· {{ link.is_enabled ? 'Enabled' : 'Disabled' }}</span>
      </p>
      <p class="text-meta break-all">
        {{ link.payment_url }}
      </p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          size="sm"
          variant="secondary"
          :disabled="busy"
          @click="edit(link)"
        >
          Edit
        </AppButton>
        <AppButton
          size="sm"
          variant="ghost"
          :disabled="busy"
          @click="removing=link;show=false;error=''"
        >
          Remove
        </AppButton>
        <AppButton
          v-if="link.is_enabled"
          size="sm"
          variant="ghost"
          :disabled="busy"
          @click="mutate(()=>service.setDefaultPaymentLink(link.is_default ? null : link.id))"
        >
          {{ link.is_default ? 'Clear default' : 'Set as default' }}
        </AppButton>
      </div>
    </article>
    <AppButton
      v-if="!show"
      variant="secondary"
      size="sm"
      :disabled="busy"
      @click="edit()"
    >
      Add payment link
    </AppButton>
    <form
      v-if="show"
      class="space-y-3"
      @submit.prevent="save"
    >
      <h3 class="font-medium">
        {{ form.id ? 'Edit payment link' : 'Add payment link' }}
      </h3>
      <label
        for="payment-provider"
        class="block text-sm"
      >Provider</label>
      <select
        id="payment-provider"
        v-model="form.provider"
        class="block w-full min-w-0 rounded-lg border border-line p-2 focus-ring"
        :disabled="busy"
        @change="error=''"
      >
        <option
          v-for="(provider,key) in paymentProviders"
          :key="key"
          :value="key"
        >
          {{ provider.name }}
        </option>
      </select>
      <p
        id="payment-link-help"
        class="text-meta text-muted"
      >
        {{ paymentProviders[form.provider].help }}
      </p>
      <template v-if="form.provider==='custom'">
        <label
          for="payment-link-label"
          class="block text-sm"
        >Label</label>
        <input
          id="payment-link-label"
          v-model="form.label"
          class="block w-full min-w-0 rounded-lg border border-line p-2 focus-ring"
          maxlength="60"
          :disabled="busy"
          :aria-invalid="!!error"
          aria-describedby="payment-link-error"
        >
      </template>
      <label
        for="payment-link-url"
        class="block text-sm"
      >Payment link</label>
      <input
        id="payment-link-url"
        v-model="form.url"
        type="text"
        inputmode="url"
        autocomplete="off"
        autocapitalize="none"
        spellcheck="false"
        maxlength="2048"
        class="block w-full min-w-0 rounded-lg border border-line p-2 focus-ring"
        :disabled="busy"
        :aria-invalid="!!error"
        aria-describedby="payment-link-help payment-link-error"
      >
      <label class="flex gap-2 items-center text-sm"><input
        v-model="form.enabled"
        type="checkbox"
        :disabled="busy"
      >Enabled</label>
      <div class="flex flex-wrap gap-2">
        <AppButton
          type="submit"
          :loading="busy"
          size="sm"
        >
          Save payment link
        </AppButton>
        <AppButton
          variant="ghost"
          size="sm"
          :disabled="busy"
          @click="show=false;error=''"
        >
          Cancel
        </AppButton>
      </div>
    </form>
    <div
      v-if="removing"
      role="group"
      aria-label="Remove payment link confirmation"
      class="space-y-3 rounded-lg border border-line p-3"
    >
      <p>Remove {{ removing.display_label }} payment link? People won't be able to use this link for reimbursements.</p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          size="sm"
          :loading="busy"
          @click="mutate(()=>service.deleteMyPaymentLink(removing!.id))"
        >
          Confirm removal
        </AppButton>
        <AppButton
          size="sm"
          variant="ghost"
          :disabled="busy"
          @click="removing=null"
        >
          Keep link
        </AppButton>
      </div>
    </div>
    <p
      id="payment-link-error"
      role="alert"
      class="text-meta text-danger"
    >
      {{ error }}
    </p>
  </section>
</template>

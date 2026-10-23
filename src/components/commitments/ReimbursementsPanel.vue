<script setup lang="ts">
import ReimbursementCard from "./ReimbursementCard.vue";
import { computed, nextTick, onMounted, watch, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useProjectContext } from '@/composables/useProjectContext';
import { useMoney } from '@/composables/useMoney';
import { useReimbursements, useRefreshReimbursements } from '@/composables/useReimbursements';
import { createReimbursement, cancelReimbursement, reimbursementSuggestions } from '@/services/reimbursements';
import { toAppError } from '@/lib/errors';
import type { Payment } from '@/services/payments';
import type { MemberDirectoryEntry } from '@/types/derived';
import type { Reimbursement, ReimbursementSuggestion } from '@/types/reimbursements';
import AppButton from '@/components/ui/AppButton.vue';
const props = defineProps<{ projectId: string; activityId: string; currency: string; payments: Payment[]; members: MemberDirectoryEntry[]; canEdit: boolean }>();
const route = useRoute();
const { context, isOrganizer } = useProjectContext();
const { format } = useMoney();
const query = useReimbursements(() => props.projectId, () => props.activityId);
const refresh = useRefreshReimbursements(props.projectId);
const sources = computed(() => props.payments.filter(p => p.status === 'paid' && p.direction === 'outgoing' && !p.settlement_group_id && p.paid_by_member_id && (isOrganizer.value || p.paid_by_member_id === context.value?.memberId)));
const show = ref(false), source = ref(''), busy = ref(false), error = ref('');
const suggestions = ref<ReimbursementSuggestion[]>([]), selected = ref<string[]>([]);
const cancellingAcknowledged = ref(false);
const cancelling = ref<Reimbursement | null>(null);
const total = computed(() => suggestions.value.filter(s => selected.value.includes(s.debtor_member_id)).reduce((sum, s) => sum + s.amount_minor, 0));
async function load() {
  error.value = ''; suggestions.value = []; selected.value = [];
  if (!source.value) return;
  busy.value = true;
  try { suggestions.value = await reimbursementSuggestions(source.value); selected.value = suggestions.value.map(s => s.debtor_member_id); }
  catch (e) { error.value = toAppError(e).message; } finally { busy.value = false; }
}
async function start() { show.value = true; source.value = sources.value.length === 1 ? sources.value[0]!.id : ''; await load(); }
async function create() {
  if (busy.value || !selected.value.length) return;
  busy.value = true; error.value = '';
  try {
    // Each source/member RPC is idempotent; a partial network retry returns existing IDs.
    for (const s of suggestions.value.filter(s => selected.value.includes(s.debtor_member_id))) await createReimbursement({ paymentId: source.value, memberId: s.debtor_member_id, amount: s.amount_minor });
    show.value = false;
  } catch (e) { error.value = toAppError(e).message; }
  finally { await refresh(); busy.value = false; }
}
async function cancel() {
  if (!cancelling.value || busy.value) return;
  busy.value = true; error.value = '';
  try { await cancelReimbursement(cancelling.value.id); cancelling.value = null; await refresh(); }
  catch (e) { error.value = toAppError(e).message; } finally { busy.value = false; }
}
async function focusRequestedSection() { if (route.query.section === 'reimbursements') { await nextTick(); document.getElementById('activity-reimbursements')?.focus(); } }
onMounted(focusRequestedSection);
watch(() => route.query.section, focusRequestedSection);
</script>
<template>
  <section
    id="activity-reimbursements"
    tabindex="-1"
    aria-label="Reimbursements"
    class="mt-6 min-w-0 space-y-3 [overflow-wrap:anywhere]"
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h3 class="text-14 font-semibold">
        Reimbursements
      </h3>
      <AppButton
        v-if="canEdit && sources.length && !show"
        size="sm"
        variant="secondary"
        @click="start"
      >
        Create reimbursements
      </AppButton>
    </div>
    <p class="text-13 text-muted">
      Requests between people explain existing balances. They do not add to project spending.
    </p>
    <p
      v-if="query.isPending.value"
      class="text-13"
    >
      Loading reimbursements…
    </p>
    <p
      v-else-if="query.isError.value"
      role="alert"
      class="text-danger"
    >
      Could not load reimbursements. <button
        class="underline"
        @click="query.refetch()"
      >
        Retry
      </button>
    </p>
    <p
      v-else-if="!query.data.value?.length"
      class="text-13 text-muted"
    >
      No reimbursements requested.
    </p>
    <ReimbursementCard
      v-for="r in query.data.value"
      :key="r.id"
      :r="r"
      @cancel="(request, acknowledged) => { cancelling=request; cancellingAcknowledged=acknowledged; error=''; }"
    />
    <form
      v-if="show"
      class="rounded-lg border border-line p-3 space-y-3 text-13"
      @submit.prevent="create"
    >
      <label class="block">Paid payment<select
        v-model="source"
        aria-label="Paid payment"
        :disabled="busy"
        required
        class="mt-1 block w-full min-w-0 rounded border border-line p-2"
        @change="load"
      ><option value="">Choose a paid payment</option><option
        v-for="p in sources"
        :key="p.id"
        :value="p.id"
      >{{ format(p.amount_minor, currency) }} paid by {{ members.find(m=>m.member_id===p.paid_by_member_id)?.display_name ?? 'Former member' }} · {{ p.paid_on }}</option></select></label>
      <p v-if="source && !busy && !error && !suggestions.length">
        No reimbursements needed. There are no unrequested amounts available in the current balances.
      </p>
      <label
        v-for="s in suggestions"
        :key="s.debtor_member_id"
        class="flex items-start gap-2"
      ><input
        v-model="selected"
        :value="s.debtor_member_id"
        type="checkbox"
        :disabled="busy"
        class="mt-1"
      ><span class="min-w-0">{{ s.debtor_name }} · {{ format(s.amount_minor, currency) }} owed to {{ s.creditor_name }}</span></label>
      <p v-if="suggestions.length">
        Total requested {{ format(total, currency) }}
      </p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          type="submit"
          size="sm"
          :disabled="!selected.length"
          :loading="busy"
        >
          Create selected reimbursements
        </AppButton><AppButton
          size="sm"
          variant="ghost"
          :disabled="busy"
          @click="show=false;error=''"
        >
          Close
        </AppButton>
      </div>
    </form>
    <div
      v-if="cancelling"
      class="rounded-lg border border-line p-3 text-13 space-y-2"
      role="group"
      aria-label="Cancel reimbursement confirmation"
    >
      <p v-if="cancellingAcknowledged">
        {{ cancelling.debtor_name }} marked this payment as sent. Cancelling will not record a settlement.
      </p>
      <p>Cancel {{ cancelling.debtor_name }}'s {{ format(cancelling.amount_minor, cancelling.currency) }} reimbursement? The payment and shares will stay unchanged.</p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          size="sm"
          :loading="busy"
          @click="cancel"
        >
          Confirm cancellation
        </AppButton><AppButton
          size="sm"
          variant="ghost"
          :disabled="busy"
          @click="cancelling=null"
        >
          Keep reimbursement
        </AppButton>
      </div>
    </div>
    <p
      v-if="error"
      role="alert"
      class="text-13 text-danger"
    >
      {{ error }}
    </p>
  </section>
</template>

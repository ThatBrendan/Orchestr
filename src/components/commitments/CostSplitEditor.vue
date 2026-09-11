<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import { useCostShares } from "@/composables/useCostShares";
import { useMoney } from "@/composables/useMoney";
import { currencyDigits } from "@/lib/money";
import { evenShares, shareInput } from "@/lib/costSharing";
import type { Commitment } from "@/services/commitments";
import type { MemberDirectoryEntry } from "@/types/derived";
import type { Json } from "@/types/database";
import AppButton from "@/components/ui/AppButton.vue";
const props = defineProps<{ commitment?: Commitment | null; cost: number | null; currency: string; members: MemberDirectoryEntry[]; readonly?: boolean }>();
const query = useCostShares(() => props.commitment?.id);
const { format, toMinor } = useMoney();
const mode = ref(props.commitment ? props.commitment.cost_split_mode ?? 'legacy' : 'none');
const selected = ref<string[]>([]);
const amounts = reactive<Record<string, string>>({});
const dirty = ref(false);
const reviewedCost = ref(props.cost);
const candidates = computed(() => props.members.filter(m => m.status === 'active' || selected.value.includes(m.member_id)));
watch(query.data, rows => {
  if (dirty.value || !rows) return;
  selected.value = rows.map(r => r.member_id);
  for (const row of rows) amounts[row.member_id] = shareInput(row.amount_minor, currencyDigits(props.currency));
}, { immediate: true });
const allocated = computed(() => {
  try { return selected.value.reduce((sum, id) => sum + (toMinor(amounts[id], props.currency) ?? 0), 0); }
  catch { return null; }
});
const originalCost = computed(() => props.commitment ? props.commitment.actual_cost_minor ?? props.commitment.confirmed_cost_minor ?? props.commitment.estimated_cost_minor : null);
const changedCost = computed(() => props.commitment && props.cost !== originalCost.value);
function recalculate() {
  if (props.cost == null || !selected.value.length) return;
  for (const [id, amount] of Object.entries(evenShares(props.cost, selected.value))) amounts[id] = shareInput(amount, currencyDigits(props.currency));
  reviewedCost.value = props.cost; dirty.value = true;
}
function changeMode() {
  dirty.value = true;
  if (mode.value === 'even') recalculate();
}
function getSplit(): Json | undefined {
  if (props.commitment && (query.isPending.value || query.isError.value)) throw new Error('Wait for the existing cost split to load before saving.');
  if (mode.value === 'legacy') {
    if (changedCost.value && selected.value.length) throw new Error('Cost changed. Choose No split, Split evenly or Custom split to review responsibility before saving.');
    return undefined;
  }
  if (!dirty.value && props.commitment && !changedCost.value) return undefined;
  if (mode.value === 'none') return { mode: 'none' };
  if (props.cost == null || !selected.value.length) throw new Error('Select participants and enter a cost to split.');
  if (mode.value === 'even' && reviewedCost.value !== props.cost) throw new Error('Cost changed. Recalculate evenly before saving.');
  const parsed = Object.fromEntries(selected.value.map(id => [id, toMinor(amounts[id], props.currency)]));
  if (Object.values(parsed).some(v => v == null) || allocated.value !== props.cost) throw new Error('The cost split must equal the Activity cost exactly.');
  return { mode: mode.value, cost: props.cost, members: selected.value, amounts: parsed };
}
defineExpose({ getSplit });
</script>
<template>
  <section class="rounded-xl border border-line p-4 space-y-3 mt-4">
    <h3 class="font-medium text-14">
      Cost sharing
    </h3>
    <p
      v-if="commitment && query.isPending.value"
      class="text-13"
    >
      Loading cost split…
    </p>
    <div
      v-else-if="query.isError.value"
      role="alert"
      class="text-13 text-danger"
    >
      Could not load the cost split. <button
        type="button"
        class="underline"
        @click="query.refetch()"
      >
        Retry
      </button>
    </div>
    <template v-else>
      <p
        v-if="readonly"
        class="text-13"
      >
        {{ mode === 'none' ? 'No split' : mode === 'legacy' ? 'Existing participant allocation' : mode === 'even' ? 'Split evenly' : 'Custom split' }}
      </p>
      <template v-else>
        <label class="block text-13">Split cost
          <select
            v-model="mode"
            class="block mt-1 w-full border border-line rounded-lg p-2 bg-surface"
            @change="changeMode"
          >
            <option
              v-if="commitment && commitment.cost_split_mode == null"
              value="legacy"
            >Keep existing allocation</option>
            <option value="none">No split</option><option value="even">Split evenly</option><option value="custom">Custom split</option>
          </select>
        </label>
        <p
          v-if="changedCost && mode !== 'none'"
          class="text-13 text-amber"
        >
          Cost changed from {{ format(originalCost, currency) }} to {{ format(cost, currency) }}. Review the split before saving.
        </p>
        <p
          v-if="mode === 'legacy'"
          class="text-13 text-muted"
        >
          Existing allocations are preserved. Choose a split mode to change responsibility.
        </p>
      </template>
      <template v-if="mode !== 'none'">
        <div
          v-for="member in candidates.filter(m => !readonly || selected.includes(m.member_id))"
          :key="member.member_id"
          class="flex flex-wrap items-center gap-3 text-13"
        >
          <label class="flex gap-2 items-center flex-1">
            <input
              v-if="!readonly && mode !== 'legacy'"
              v-model="selected"
              type="checkbox"
              :value="member.member_id"
              :disabled="member.status !== 'active'"
              @change="dirty = true; mode === 'even' && recalculate()"
            >
            {{ member.display_name }}<span v-if="member.status !== 'active'"> (removed)</span>
          </label>
          <input
            v-if="!readonly && mode === 'custom' && selected.includes(member.member_id)"
            v-model="amounts[member.member_id]"
            type="text"
            inputmode="decimal"
            class="border border-line rounded p-2 w-28"
            :aria-label="`${member.display_name} share (${currency})`"
            @input="dirty = true"
          >
          <span v-else-if="selected.includes(member.member_id)">{{ query.data.value && !dirty ? format(query.data.value.find(r => r.member_id === member.member_id)?.amount_minor, currency) : amounts[member.member_id] ? `${amounts[member.member_id]} ${currency}` : '—' }}</span>
          <button
            v-if="!readonly && mode !== 'legacy' && member.status !== 'active' && selected.includes(member.member_id)"
            type="button"
            class="underline"
            @click="selected = selected.filter(id => id !== member.member_id); dirty = true"
          >
            Remove from split
          </button>
        </div>
        <AppButton
          v-if="!readonly && mode === 'even'"
          type="button"
          size="sm"
          variant="secondary"
          @click="recalculate"
        >
          Recalculate evenly
        </AppButton>
        <p
          v-if="mode !== 'legacy'"
          class="text-13"
          aria-live="polite"
        >
          {{ format(allocated, currency) }} of {{ format(cost, currency) }} allocated<span v-if="allocated != null && cost != null && allocated !== cost"> · {{ format(Math.abs(cost - allocated), currency) }} {{ allocated > cost ? 'over' : 'remaining' }}</span>
        </p>
      </template>
      <p class="text-13 text-muted">
        Cost sharing records responsibility. It does not create payments.
      </p>
    </template>
  </section>
</template>

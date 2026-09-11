<script setup lang="ts">
import CostSplitEditor from "./CostSplitEditor.vue";
import type { MemberDirectoryEntry } from "@/types/derived";
import { computed, ref, watch } from "vue";
import { useMoney } from "@/composables/useMoney";
import { useFinancialPlanning } from "@/composables/useFinancialPlanning";
import { toAppError } from "@/lib/errors";
import type { Commitment } from "@/services/commitments";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
const props = defineProps<{ open: boolean; projectId: string; currency: string; commitment: Commitment; complete: boolean; members: MemberDirectoryEntry[] }>();
const emit = defineEmits<{ close: [] }>();
const { format, toMajor, toMinor } = useMoney();
const { actual } = useFinancialPlanning();
const draft = ref("");
const error = ref("");
const splitEditor = ref<InstanceType<typeof CostSplitEditor>>();
const splitCost = computed(() => { try { return toMinor(draft.value, props.currency) ?? props.commitment.confirmed_cost_minor ?? props.commitment.estimated_cost_minor; } catch { return null; } });
watch(() => props.open, (open) => {
  if (open) {
    const amount = props.commitment.actual_cost_minor ?? (props.complete ? props.commitment.confirmed_cost_minor ?? props.commitment.estimated_cost_minor : null);
    draft.value = String(toMajor(amount, props.currency) ?? ""); error.value = "";
  }
});
async function save() {
  if (actual.isPending.value) return;
  error.value = "";
  try {
    const amount = toMinor(draft.value, props.currency);
    if (props.complete && amount == null) throw new Error("Confirm the final cost, including zero if nothing was spent.");
    await actual.mutateAsync({ projectId: props.projectId, id: props.commitment.id, amount, complete: props.complete, split: splitEditor.value?.getSplit() });
    emit("close");
  } catch (e) { error.value = toAppError(e).message; }
}
</script>
<template>
  <AppModal
    :open="open"
    :busy="actual.isPending.value"
    :title="complete ? 'Complete activity' : 'Edit final cost'"
    @close="emit('close')"
  >
    <p class="mb-4 text-14">
      Estimated cost: {{ format(commitment.estimated_cost_minor, currency) }}
    </p>
    <form @submit.prevent="save">
      <label class="block text-14">
        <span class="block mb-2">What was the final cost? ({{ currency }})</span>
        <input
          v-model="draft"
          type="text"
          inputmode="decimal"
          :required="complete"
          :disabled="actual.isPending.value"
          class="w-full rounded-lg border border-line px-3 py-2 focus-ring"
        >
      </label>
      <p class="mt-2 text-13 text-muted">
        This preserves the estimate and does not record a payment.
      </p>
      <p
        v-if="!complete"
        class="mt-2 text-13 text-muted"
      >
        Leave blank if the final cost is not yet known.
      </p>
      <p
        v-if="error"
        role="alert"
        class="mt-3 text-13 text-danger"
      >
        {{ error }}
      </p>
    </form>
    <CostSplitEditor
      v-if="open"
      ref="splitEditor"
      :commitment="commitment"
      :cost="splitCost"
      :currency="currency"
      :members="members"
    />
    <template #footer>
      <AppButton
        size="sm"
        variant="secondary"
        :disabled="actual.isPending.value"
        @click="emit('close')"
      >
        Cancel
      </AppButton>
      <AppButton
        size="sm"
        :loading="actual.isPending.value"
        @click="save"
      >
        {{ complete ? 'Complete' : 'Save final cost' }}
      </AppButton>
    </template>
  </AppModal>
</template>

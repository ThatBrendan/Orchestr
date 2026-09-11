<script setup lang="ts">
import { ref, watch } from "vue";
import { useMoney } from "@/composables/useMoney";
import { useFinancialPlanning } from "@/composables/useFinancialPlanning";
import { toAppError } from "@/lib/errors";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
const props = defineProps<{ open: boolean; projectId: string; currency: string; target: number | null }>();
const emit = defineEmits<{ close: [] }>();
const { toMinor, toMajor } = useMoney();
const { budget } = useFinancialPlanning();
const draft = ref("");
const error = ref("");
const clearOpen = ref(false);
watch(() => props.open, (open) => { if (open) { draft.value = String(toMajor(props.target, props.currency) ?? ""); error.value = ""; clearOpen.value = false; } });
async function save(clear = false) {
  if (budget.isPending.value) return;
  error.value = "";
  try {
    const amount = clear ? null : toMinor(draft.value, props.currency);
    if (amount === null && !clear) throw new Error("Enter a budget, including zero if appropriate.");
    await budget.mutateAsync({ projectId: props.projectId, amount });
    clearOpen.value = false;
    emit("close");
  } catch (e) { error.value = toAppError(e).message; clearOpen.value = false; }
}
</script>
<template>
  <AppModal
    :open="open"
    :busy="budget.isPending.value"
    :title="target == null ? 'Set project budget' : 'Edit project budget'"
    @close="emit('close')"
  >
    <form @submit.prevent="save()">
      <label class="block text-14">
        <span class="block mb-2">Approximate total budget ({{ currency }})</span>
        <input
          v-model="draft"
          type="text"
          inputmode="decimal"
          required
          :disabled="budget.isPending.value"
          class="w-full rounded-lg border border-line px-3 py-2 focus-ring"
        >
      </label>
      <p
        v-if="error"
        role="alert"
        class="mt-3 text-13 text-danger"
      >
        {{ error }}
      </p>
    </form>
    <AppConfirmDialog
      :open="clearOpen"
      title="Clear budget"
      message="Remove the budget target? Activity costs and payment history will be kept."
      confirm-label="Clear budget"
      :loading="budget.isPending.value"
      @close="clearOpen = false"
      @confirm="save(true)"
    />
    <template #footer>
      <AppButton
        v-if="target != null"
        size="sm"
        variant="ghost"
        :disabled="budget.isPending.value"
        @click="clearOpen = true"
      >
        Clear budget
      </AppButton>
      <AppButton
        size="sm"
        variant="secondary"
        :disabled="budget.isPending.value"
        @click="emit('close')"
      >
        Cancel
      </AppButton>
      <AppButton
        size="sm"
        :loading="budget.isPending.value"
        @click="save()"
      >
        Save budget
      </AppButton>
    </template>
  </AppModal>
</template>

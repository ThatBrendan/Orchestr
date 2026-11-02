<script setup lang="ts">
import { ref } from "vue";
import { DateTime } from "luxon";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { useMoney } from "@/composables/useMoney";
import { saveDecision } from "@/services/decisions";
import { toAppError } from "@/lib/errors";
import type { Decision } from "@/types/decisions";
const props = defineProps<{ projectId: string; currency: string; timezone: string; decision?: Decision }>();
const emit = defineEmits<{ close: []; saved: [id: string] }>();
const money = useMoney(), id = props.decision?.id ?? crypto.randomUUID();
const title = ref(props.decision?.title ?? ""), description = ref(props.decision?.description ?? "");
const deadline = ref(props.decision?.voting_deadline ? DateTime.fromISO(props.decision.voting_deadline, { zone: props.timezone }).toISODate()! : "");
const initialDeadline = deadline.value;
const options = ref(props.decision?.options.map(o => ({ title: o.title, cost: String(money.toMajor(o.estimated_cost_minor, props.currency) ?? "") })) ?? [{ title: "", cost: "" }, { title: "", cost: "" }]);
const busy = ref(false), error = ref("");
async function save() {
  if (busy.value) return;
  error.value = "";
  if (deadline.value && !DateTime.fromISO(deadline.value, { zone: props.timezone }).isValid) {
    error.value = "Choose a valid date in the project timezone."; return;
  }
  let values;
  try { values = options.value.map(o => ({ title: o.title.trim(), estimated_cost_minor: o.cost.trim() ? money.toMinor(o.cost, props.currency) : null })); } catch (e) { error.value = e instanceof Error ? e.message : "Enter valid estimated costs."; return; }
  if (options.value.some((o, i) => o.cost.trim() && values[i]?.estimated_cost_minor == null)) { error.value = "Enter valid estimated costs."; return; }
  busy.value = true;
  try {
    await saveDecision(props.projectId, id, { title: title.value, description: description.value || null, deadline: deadline.value || null, preserveDeadline: !!props.decision && deadline.value === initialDeadline, options: props.decision?.voting_started ? null : values }, !!props.decision);
    emit("saved", id);
  } catch (e) { error.value = toAppError(e).message; }
  finally { busy.value = false; }
}
</script>
<template>
  <AppModal
    :open="true"
    :title="decision ? 'Edit decision' : 'New decision'"
    :busy="busy"
    @close="emit('close')"
  >
    <form
      class="space-y-4"
      @submit.prevent="save"
    >
      <label class="block text-sm">Question<input
        v-model="title"
        class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
        required
        maxlength="200"
        autofocus
      ></label>
      <fieldset
        :disabled="decision?.voting_started"
        class="space-y-4"
      >
        <legend class="text-sm font-medium">
          Options
        </legend>
        <p
          v-if="decision?.voting_started"
          class="text-meta text-muted"
        >
          Options stay fixed once voting has begun.
        </p>
        <div
          v-for="(option, index) in options"
          :key="index"
          class="border-t border-line pt-4 space-y-2"
        >
          <label class="block text-sm">Option {{ index + 1 }}<input
            v-model="option.title"
            class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
            required
            maxlength="200"
          ></label>
          <label class="block text-meta">Estimated cost ({{ currency }}, optional)<input
            v-model="option.cost"
            class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
            inputmode="decimal"
          ></label>
          <AppButton
            v-if="options.length > 2 && !decision?.voting_started"
            type="button"
            variant="ghost"
            @click="options.splice(index, 1)"
          >
            Remove option {{ index + 1 }}
          </AppButton>
        </div>
        <AppButton
          v-if="!decision?.voting_started && options.length < 20"
          type="button"
          variant="secondary"
          @click="options.push({ title: '', cost: '' })"
        >
          Add option
        </AppButton>
      </fieldset>
      <label class="block text-sm">Deadline date (optional)<input
        v-model="deadline"
        type="date"
        class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
      ></label>
      <p
        v-if="!decision || deadline !== initialDeadline"
        class="text-meta text-muted"
      >
        Voting closes at 23:59:59 on this date in {{ timezone }}. The final choice is made manually.
      </p>
      <p
        v-if="decision && deadline === initialDeadline && decision.voting_deadline"
        class="text-meta text-muted"
      >
        Current deadline: {{ DateTime.fromISO(decision.voting_deadline, { zone: timezone }).toFormat('dd LLL yyyy HH:mm:ss') }} ({{ timezone }}). Change the date to use end of day.
      </p>
      <label class="block text-sm">Description (optional)<textarea
        v-model="description"
        class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
        maxlength="4000"
        rows="2"
      /></label>
      <p
        v-if="error"
        role="alert"
        class="text-danger text-sm"
      >
        {{ error }}
      </p>
      <div class="flex justify-end gap-2">
        <AppButton
          type="button"
          variant="secondary"
          :disabled="busy"
          @click="emit('close')"
        >
          Cancel
        </AppButton><AppButton
          type="submit"
          :disabled="busy"
        >
          {{ busy ? 'Saving…' : 'Save decision' }}
        </AppButton>
      </div>
    </form>
  </AppModal>
</template>

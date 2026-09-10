<script setup lang="ts">
import { reactive, ref, watch } from "vue";
import { useCreateMilestone, useUpdateMilestone } from "@/composables/useMilestones";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import type { Milestone } from "@/services/milestones";
import type { Commitment } from "@/services/commitments";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";

const props = defineProps<{
  open: boolean;
  projectId: string;
  commitments: Commitment[];
  /** null = create mode */
  milestone: Milestone | null;
}>();
const emit = defineEmits<{ close: [] }>();

const create = useCreateMilestone(props.projectId);
const update = useUpdateMilestone(props.projectId);
const toast = useToast();

const form = reactive({ title: "", on_date: "", commitment_id: "", notes: "" });
const fieldError = ref<string | null>(null);

watch(
  () => [props.open, props.milestone],
  () => {
    const m = props.milestone;
    form.title = m?.title ?? "";
    form.on_date = m?.on_date ?? "";
    form.commitment_id = m?.commitment_id ?? "";
    form.notes = m?.notes ?? "";
    fieldError.value = null;
  },
  { immediate: true },
);

async function submit() {
  if (create.isPending.value || update.isPending.value) return;
  fieldError.value = null;
  if (!form.title.trim()) {
    fieldError.value = "Give the milestone a title.";
    return;
  }
  if (!form.on_date) {
    fieldError.value = "Pick a date.";
    return;
  }
  const payload = {
    title: form.title.trim(),
    on_date: form.on_date,
    commitment_id: form.commitment_id || null,
    notes: form.notes.trim() || null,
  };
  try {
    if (props.milestone) {
      await update.mutateAsync({ id: props.milestone.id, patch: payload });
      toast.success("Milestone updated.");
    } else {
      await create.mutateAsync({ ...payload, project_id: props.projectId });
      toast.success("Milestone created.");
    }
    emit("close");
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}
</script>

<template>
  <AppModal :busy="create.isPending.value || update.isPending.value" :open="props.open" :title="props.milestone ? 'Edit milestone' : 'New milestone'" @close="emit('close')">
    <form class="space-y-4" @submit.prevent="submit">
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Title</span>
        <input v-model="form.title" required class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
      </label>
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Date</span>
        <input v-model="form.on_date" type="date" required class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line" />
      </label>
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Linked activity</span>
        <select v-model="form.commitment_id" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface">
          <option value="">None</option>
          <option v-for="c in props.commitments" :key="c.id" :value="c.id">{{ c.title }}</option>
        </select>
      </label>
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Notes</span>
        <textarea v-model="form.notes" rows="2" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
      </label>
      <p v-if="fieldError" class="text-13 text-danger">{{ fieldError }}</p>
    </form>
    <template #footer>
      <AppButton variant="secondary" size="sm" :disabled="create.isPending.value || update.isPending.value" @click="emit('close')">Cancel</AppButton>
      <AppButton size="sm" :loading="create.isPending.value || update.isPending.value" @click="submit">
        {{ props.milestone ? "Save" : "Create milestone" }}
      </AppButton>
    </template>
  </AppModal>
</template>

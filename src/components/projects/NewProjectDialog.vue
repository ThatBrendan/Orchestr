<script setup lang="ts">
import { ref, reactive } from "vue";
import { useRouter } from "vue-router";
import { DateTime } from "luxon";
import { useCreateProject } from "@/composables/useProjects";
import { useMyProfile } from "@/composables/useDashboard";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const router = useRouter();
const toast = useToast();
const { profile } = useMyProfile();
const create = useCreateProject();

const CURRENCIES = ["GBP", "EUR", "USD", "AUD", "CAD"];
const form = reactive({
  name: "",
  starts_on: "",
  ends_on: "",
  currency: "GBP",
});
const fieldError = ref<string | null>(null);

async function submit() {
  fieldError.value = null;
  if (!form.name.trim()) {
    fieldError.value = "Give the project a name.";
    return;
  }
  if (form.starts_on && form.ends_on && form.ends_on < form.starts_on) {
    fieldError.value = "The end date must be on or after the start date.";
    return;
  }
  try {
    const { id } = await create.mutateAsync({
      name: form.name.trim(),
      timezone: profile.value?.timezone ?? DateTime.local().zoneName ?? "UTC",
      currency: form.currency,
      starts_on: form.starts_on || null,
      ends_on: form.ends_on || null,
    });
    toast.success("Project created.");
    emit("close");
    await router.push({ name: "project.overview", params: { projectId: id } });
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}
</script>

<template>
  <AppModal :open="props.open" title="New project" @close="emit('close')">
    <form class="space-y-4" @submit.prevent="submit">
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Name</span>
        <input
          v-model="form.name"
          required
          placeholder="e.g. Barcelona Stag Weekend"
          class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line"
        />
      </label>
      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Start date</span>
          <input v-model="form.starts_on" type="date" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line" />
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">End date</span>
          <input v-model="form.ends_on" type="date" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line" />
        </label>
      </div>
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Currency</span>
        <select v-model="form.currency" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface">
          <option v-for="c in CURRENCIES" :key="c" :value="c">{{ c }}</option>
        </select>
        <span class="text-13 text-muted mt-1 block">Can't be changed once the project has costs.</span>
      </label>
      <p v-if="fieldError" class="text-13 text-danger">{{ fieldError }}</p>
    </form>

    <template #footer>
      <AppButton variant="secondary" size="sm" @click="emit('close')">Cancel</AppButton>
      <AppButton size="sm" :loading="create.isPending.value" @click="submit">Create project</AppButton>
    </template>
  </AppModal>
</template>

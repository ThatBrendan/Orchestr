<script setup lang="ts">
import { computed, ref, reactive, watch } from "vue";
import { useRouter } from "vue-router";
import { DateTime } from "luxon";
import { useCreateProject } from "@/composables/useProjects";
import { useMyProfile } from "@/composables/useDashboard";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import { DEFAULT_PROJECT_PROFILE, PROJECT_PROFILES, profileDefinition } from "@/lib/projectProfiles";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import type { ProjectProfile } from "@/types/database";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const router = useRouter();
const toast = useToast();
const { profile } = useMyProfile();
const create = useCreateProject();

const CURRENCIES = ["GBP", "EUR", "USD", "AUD", "CAD"];
const step = ref<"profile" | "details">("profile");
const form = reactive({
  profile: DEFAULT_PROJECT_PROFILE as ProjectProfile,
  name: "",
  timezone: "",
  starts_on: "",
  ends_on: "",
  currency: "GBP",
});
const fieldError = ref<string | null>(null);
const selectedProfile = computed(() => profileDefinition(form.profile));

watch(
  () => props.open,
  (open) => {
    if (!open) return;
    step.value = "profile";
    fieldError.value = null;
    Object.assign(form, {
      profile: DEFAULT_PROJECT_PROFILE,
      name: "",
      timezone: profile.value?.timezone ?? DateTime.local().zoneName ?? "UTC",
      starts_on: "",
      ends_on: "",
      currency: profile.value?.default_currency ?? "GBP",
    });
  },
  { immediate: true },
);

function chooseProfile(profileValue: ProjectProfile) {
  form.profile = profileValue;
}

function continueToDetails() {
  fieldError.value = null;
  step.value = "details";
}

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
      profile: form.profile,
      timezone: form.timezone.trim() || profile.value?.timezone || DateTime.local().zoneName || "UTC",
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
  <AppModal :open="props.open" :title="step === 'profile' ? 'What are you planning?' : 'New project'" size="lg" @close="emit('close')">
    <div v-if="step === 'profile'" class="grid gap-3 sm:grid-cols-2">
      <button
        v-for="profileOption in PROJECT_PROFILES"
        :key="profileOption.value"
        type="button"
        class="rounded-xl border p-4 text-left transition-colors focus-ring"
        :class="form.profile === profileOption.value ? 'border-ink bg-[#F6F6F4]' : 'border-line hover:bg-[#FBFBFA]'"
        :aria-pressed="form.profile === profileOption.value"
        @click="chooseProfile(profileOption.value)"
      >
        <span class="block text-14 font-semibold text-ink">{{ profileOption.label }}</span>
        <span class="mt-1 block text-13 text-ink-soft">{{ profileOption.description }}</span>
      </button>
    </div>

    <form v-else class="space-y-4" @submit.prevent="submit">
      <div class="rounded-xl border border-line bg-[#FBFBFA] px-4 py-3">
        <div class="text-13 font-medium text-muted">Profile</div>
        <div class="mt-0.5 text-14 font-semibold">{{ selectedProfile.label }}</div>
        <div class="mt-0.5 text-13 text-ink-soft">{{ selectedProfile.description }}</div>
      </div>

      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Project name</span>
        <input v-model="form.name" required maxlength="120" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
      </label>

      <div class="grid gap-3 sm:grid-cols-2">
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
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Timezone</span>
        <input v-model="form.timezone" required class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
      </label>

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
      <AppButton v-if="step === 'details'" variant="secondary" size="sm" @click="step = 'profile'">Back</AppButton>
      <AppButton v-else variant="secondary" size="sm" @click="emit('close')">Cancel</AppButton>
      <AppButton v-if="step === 'profile'" size="sm" @click="continueToDetails">Continue</AppButton>
      <AppButton v-else size="sm" :loading="create.isPending.value" @click="submit">Create project</AppButton>
    </template>
  </AppModal>
</template>

<script setup lang="ts">
import PasswordForm from "@/components/ui/PasswordForm.vue";
import { computed, ref, watch } from "vue";
import { useMyProfile, useUpdateMyDisplayName } from "@/composables/useDashboard";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import PageContainer from "@/components/ui/PageContainer.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import AppButton from "@/components/ui/AppButton.vue";

const { profile, isPending } = useMyProfile();
const updateName = useUpdateMyDisplayName();
const toast = useToast();
const editing = ref(false);
const name = ref("");
const fieldError = ref<string | null>(null);

watch(
  profile,
  (next) => {
    if (!editing.value) name.value = next?.display_name ?? "";
  },
  { immediate: true },
);

const notif = (raw: unknown) => {
  if (!raw || typeof raw !== "object") return "—";
  const p = raw as Record<string, unknown>;
  const on = [p.email ? "Email" : null, p.push ? "Push" : null].filter(Boolean);
  return on.length ? on.join(" + ") : "Off";
};

const canSave = computed(() => !!name.value.trim() && !updateName.isPending.value);

function startEdit() {
  fieldError.value = null;
  name.value = profile.value?.display_name ?? "";
  editing.value = true;
}

function cancelEdit() {
  fieldError.value = null;
  name.value = profile.value?.display_name ?? "";
  editing.value = false;
}

async function saveName() {
  fieldError.value = null;
  const trimmed = name.value.trim();
  if (!trimmed) {
    fieldError.value = "Name can't be empty.";
    return;
  }

  try {
    await updateName.mutateAsync(trimmed);
    editing.value = false;
    toast.success("Name updated.");
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}
</script>

<template>
  <PageContainer width="md">
    <h1 class="font-display text-[26px] font-semibold tracking-tight">
      Settings
    </h1>
    <p class="mt-1.5 text-14.5 text-ink-soft">
      Manage your account and preferences.
    </p>

    <div class="mt-8 space-y-2">
      <SkeletonBlock
        v-if="isPending"
        height="180px"
        rounded="0.75rem"
      />
      <div
        v-else
        class="border rounded-xl divide-y border-line bg-surface"
      >
        <div class="px-5 py-4">
          <div class="flex items-center justify-between gap-4">
            <span class="text-14 font-medium text-ink-soft">Name</span>
            <template v-if="editing">
              <input
                v-model="name"
                class="min-w-0 flex-1 rounded-lg border border-line bg-surface px-3 py-2 text-14 focus-ring sm:max-w-xs"
                maxlength="80"
                autocomplete="name"
              >
            </template>
            <span
              v-else
              class="text-14"
            >{{ profile?.display_name ?? "—" }}</span>
          </div>
          <p
            v-if="fieldError"
            class="mt-2 text-13 text-danger"
          >
            {{ fieldError }}
          </p>
          <div class="mt-3 flex justify-end gap-2">
            <template v-if="editing">
              <AppButton
                variant="secondary"
                size="sm"
                :disabled="updateName.isPending.value"
                @click="cancelEdit"
              >
                Cancel
              </AppButton>
              <AppButton
                size="sm"
                :loading="updateName.isPending.value"
                :disabled="!canSave"
                @click="saveName"
              >
                Save
              </AppButton>
            </template>
            <AppButton
              v-else
              variant="secondary"
              size="sm"
              @click="startEdit"
            >
              Edit
            </AppButton>
          </div>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Email</span>
          <span class="text-14">{{ profile?.email ?? "—" }}</span>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Timezone</span>
          <span class="text-14">{{ profile?.timezone ?? "—" }}</span>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Currency</span>
          <span class="text-14">{{ profile?.default_currency ?? "—" }}</span>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Notifications</span>
          <span class="text-14">{{ notif(profile?.notification_prefs) }}</span>
        </div>
      </div>
    </div>
    <section
      class="mt-8 max-w-sm border rounded-xl p-5 border-line bg-surface"
      aria-labelledby="change-password-title"
    >
      <h2
        id="change-password-title"
        class="mb-4 font-display text-lg font-semibold"
      >
        Change password
      </h2>
      <PasswordForm label="Change password" />
    </section>
  </PageContainer>
</template>

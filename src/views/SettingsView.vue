<script setup lang="ts">
import CalendarSyncSettings from "@/components/settings/CalendarSyncSettings.vue";
import NotificationSettings from '@/components/settings/NotificationSettings.vue';
import PaymentLinksSettings from "@/components/settings/PaymentLinksSettings.vue";
import PasswordForm from "@/components/ui/PasswordForm.vue";
import { computed, nextTick, ref, watch } from "vue";
import { useMyProfile, useUpdateMyDisplayName } from "@/composables/useDashboard";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import PageContainer from "@/components/ui/PageContainer.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { usePwaInstall } from "@/composables/usePwaInstall";

const { profile, isPending, isError, error, refetch } = useMyProfile();
const updateName = useUpdateMyDisplayName();
const toast = useToast();
const pwa = usePwaInstall();
const unavailableInstallExplanation = ref(false);
const editing = ref(false);
const nameInput = ref<HTMLInputElement | null>(null);
const editButton = ref<InstanceType<typeof AppButton> | null>(null);
watch(editing, async value => {
  await nextTick();
  if (value) nameInput.value?.focus();
  else (editButton.value?.$el as HTMLElement | undefined)?.focus();
});
const name = ref("");
const fieldError = ref<string | null>(null);

watch(
  profile,
  (next) => {
    if (!editing.value) name.value = next?.display_name ?? "";
  },
  { immediate: true },
);


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

async function handleInstallAction() {
  if (pwa.isIos.value) {
    pwa.openInstructions();
    return;
  }
  if (pwa.nativeAvailable.value) {
    await pwa.installOrchestrio();
    return;
  }
  unavailableInstallExplanation.value = true;
}
</script>

<template>
  <PageContainer width="md">
    <h1 class="font-display text-page-title font-semibold tracking-tight">
      Settings
    </h1>

    <div class="mt-8 space-y-3">
      <h2 class="text-section-heading">
        Account
      </h2>
      <SkeletonBlock
        v-if="isPending"
        role="status"
        aria-label="Loading account details"
        height="180px"
        rounded="0.75rem"
      />
      <ErrorState
        v-else-if="isError"
        :error="error"
        :retry="() => refetch()"
      />
      <div
        v-else
        class="border rounded-xl divide-y border-line bg-surface"
      >
        <div class="px-5 py-4">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <label
              v-if="editing"
              for="account-name"
            >Name</label>
            <span
              v-else
              class="text-sm font-medium text-ink-soft"
            >Name</span>
            <template v-if="editing">
              <input
                id="account-name"
                ref="nameInput"
                v-model="name"
                :aria-invalid="!!fieldError"
                :aria-describedby="fieldError ? 'account-name-error' : undefined"
                class="min-w-0 flex-1 rounded-lg border border-line bg-surface px-3 py-2 text-sm focus-ring sm:max-w-xs"
                maxlength="80"
                autocomplete="name"
              >
            </template>
            <span
              v-else
              class="min-w-0 text-sm [overflow-wrap:anywhere]"
            >{{ profile?.display_name ?? "—" }}</span>
          </div>
          <p
            v-if="fieldError"
            id="account-name-error"
            role="alert"
            class="mt-2 text-meta text-danger"
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
              ref="editButton"
              variant="secondary"
              size="sm"
              @click="startEdit"
            >
              Edit
            </AppButton>
          </div>
        </div>
        <div class="flex flex-wrap items-start justify-between gap-3 px-5 py-4">
          <span class="text-sm font-medium text-ink-soft">Email</span>
          <span class="min-w-0 text-sm [overflow-wrap:anywhere]">{{ profile?.email ?? "—" }}</span>
        </div>
        <div class="flex flex-wrap items-start justify-between gap-3 px-5 py-4">
          <span class="text-sm font-medium text-ink-soft">Timezone</span>
          <span class="min-w-0 text-sm [overflow-wrap:anywhere]">{{ profile?.timezone ?? "—" }}</span>
        </div>
        <div class="flex flex-wrap items-start justify-between gap-3 px-5 py-4">
          <span class="text-sm font-medium text-ink-soft">Currency</span>
          <span class="min-w-0 text-sm [overflow-wrap:anywhere]">{{ profile?.default_currency ?? "—" }}</span>
        </div>
      </div>
    </div>
    <section
      v-if="!pwa.isInstalled.value"
      class="mt-8 border-t border-line pt-6"
      aria-labelledby="pwa-install-title"
    >
      <h2
        id="pwa-install-title"
        class="mb-4 text-section-heading font-semibold"
      >
        App installation
      </h2>
      <div class="flex flex-col gap-4 rounded-xl border border-line bg-surface p-5 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-sm font-medium">
            Install Orchestrio
          </p>
          <p class="mt-1 text-sm text-ink-soft">
            Add Orchestrio to your device for quicker access.
          </p>
          <p
            v-if="unavailableInstallExplanation"
            role="status"
            class="mt-3 text-sm text-ink-soft"
          >
            This browser does not offer automatic installation. Look for “Install app,” “Add to Home Screen,” or a similar option in the browser menu.
          </p>
        </div>
        <AppButton
          size="sm"
          :loading="pwa.installing.value"
          @click="handleInstallAction"
        >
          {{ pwa.isIos.value ? "View installation steps" : "Install Orchestrio" }}
        </AppButton>
      </div>
    </section>
    <section
      class="mt-8 border-t border-line pt-6"
      aria-labelledby="change-password-title"
    >
      <h2
        id="change-password-title"
        class="mb-4 text-section-heading font-semibold"
      >
        Change password
      </h2>
      <PasswordForm label="Change password" />
    </section>
    <NotificationSettings />
    <PaymentLinksSettings />
    <CalendarSyncSettings />
  </PageContainer>
</template>

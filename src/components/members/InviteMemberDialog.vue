<script setup lang="ts">
import { reactive, ref } from "vue";
import { useInviteMember } from "@/composables/useMembers";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";

const props = defineProps<{ open: boolean; projectId: string }>();
const emit = defineEmits<{ close: [] }>();

const invite = useInviteMember(props.projectId);
const toast = useToast();

const form = reactive({ email: "", role: "member" as "member" | "viewer" });
const fieldError = ref<string | null>(null);
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

async function submit() {
  if (invite.isPending.value) return;
  fieldError.value = null;
  const email = form.email.trim().toLowerCase();
  if (!EMAIL_RE.test(email)) {
    fieldError.value = "Enter a valid email address.";
    return;
  }
  try {
    const result = await invite.mutateAsync({ email, role: form.role });
    toast.success(result.emailed ? "Invitation sent." : "Invitation created. Email invite delivery deferred.");
    form.email = "";
    emit("close");
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}
</script>

<template>
  <AppModal
    :busy="invite.isPending.value"
    :open="props.open"
    title="Invite someone"
    @close="emit('close')"
  >
    <p class="mb-4 text-meta text-muted">
      Create a pending invitation for this email address. Email delivery is currently deferred.
    </p>
    <form
      class="space-y-4"
      @submit.prevent="submit"
    >
      <label class="block">
        <span class="text-meta font-medium block mb-1.5 text-ink-soft">Email address</span>
        <input
          v-model="form.email"
          type="email"
          required
          placeholder="name@example.com"
          class="w-full border rounded-lg px-3.5 py-2.5 text-sm focus-ring border-line"
        >
      </label>
      <label class="block">
        <span class="text-meta font-medium block mb-1.5 text-ink-soft">Role</span>
        <select
          v-model="form.role"
          class="w-full border rounded-lg px-3 py-2.5 text-sm focus-ring border-line bg-surface"
        >
          <option value="member">Member</option>
          <option value="viewer">Viewer — can complete assigned Activities</option>
        </select>
      </label>
      <p class="text-meta text-muted">
        {{ form.role === 'member' ? 'Can edit Categories, Activities and supported payments, subject to project permissions.' : 'Can view the project but cannot make changes.' }}
      </p>
      <p
        v-if="fieldError"
        class="text-meta text-danger"
      >
        {{ fieldError }}
      </p>
    </form>
    <template #footer>
      <AppButton
        variant="secondary"
        size="sm"
        :disabled="invite.isPending.value"
        @click="emit('close')"
      >
        Cancel
      </AppButton>
      <AppButton
        size="sm"
        :loading="invite.isPending.value"
        @click="submit"
      >
        Create invitation
      </AppButton>
    </template>
  </AppModal>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useNotifications } from "@/composables/useNotifications";
import { toAppError } from "@/lib/errors";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { presentLabel } from "@/lib/presentation";

const open = ref(false);
const message = ref("");
const router = useRouter();
const { pending, respond } = useNotifications();
async function answer(token: string, action: "accept" | "decline") {
  message.value = "";
  try {
    const projectId = await respond.mutateAsync({ token, action });
    if (action === "accept") {
      open.value = false;
      await router.push({ name: "project.overview", params: { projectId } });
    } else message.value = "Invitation declined.";
  } catch (error) { message.value = toAppError(error).message; }
}
</script>

<template>
  <button
    class="ml-auto flex min-h-11 shrink-0 items-center gap-2 rounded-lg px-3 py-2 focus-ring text-13"
    aria-label="Notifications"
    @click="open = true"
  >
    <svg
      aria-hidden="true"
      class="h-5 w-5"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
    ><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" /></svg>
    <span class="hidden sm:inline">Notifications</span>
    <span
      v-if="pending.data.value?.length"
      class="rounded-full bg-accent px-2 text-white"
    >{{ pending.data.value.length }}</span>
  </button>
  <AppModal
    :open="open"
    title="Notifications"
    :busy="respond.isPending.value"
    @close="open = false"
  >
    <p
      v-if="pending.isPending.value"
      class="text-14 text-muted"
    >
      Loading invitations…
    </p>
    <div
      v-else-if="pending.isError.value"
      class="text-14 text-danger"
    >
      Could not load invitations. <button
        class="underline"
        @click="pending.refetch()"
      >
        Retry
      </button>
    </div>
    <p
      v-else-if="!pending.data.value?.length"
      class="text-14 text-muted"
    >
      No pending invitations.
    </p>
    <div class="space-y-4">
      <article
        v-for="invitation in pending.data.value"
        :key="invitation.id"
        class="border border-line rounded-lg p-4 space-y-3"
      >
        <p class="text-14">
          {{ invitation.inviter_name ?? 'Someone' }} invited you to <strong>{{ invitation.project_name }}</strong>.
        </p>
        <p class="text-13 capitalize">
          Role: {{ presentLabel(invitation.role) }}
        </p>
        <time
          class="block text-13 text-muted"
          :datetime="invitation.created_at"
        >{{ new Date(invitation.created_at).toLocaleDateString() }}</time>
        <div class="flex gap-2">
          <AppButton
            variant="secondary"
            size="sm"
            :disabled="respond.isPending.value"
            @click="answer(invitation.token, 'decline')"
          >
            Decline
          </AppButton>
          <AppButton
            size="sm"
            :disabled="respond.isPending.value"
            @click="answer(invitation.token, 'accept')"
          >
            Accept
          </AppButton>
        </div>
      </article>
    </div>
    <p
      v-if="message"
      role="status"
      class="mt-3 text-14"
    >
      {{ message }}
    </p>
  </AppModal>
</template>

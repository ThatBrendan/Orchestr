<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { activityNotificationRoute, type ActivityNotification } from "@/services/notifications";
import { useNotifications } from "@/composables/useNotifications";
import { toAppError } from "@/lib/errors";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { presentLabel } from "@/lib/presentation";

const open = ref(false);
const message = ref("");
const router = useRouter();
const { pending, respond, activity, markRead, unreadCount } = useNotifications();
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
async function openActivity(item: ActivityNotification) {
  if (markRead.isPending.value) return;
  message.value = "";
  try {
    await markRead.mutateAsync(item.id);
    open.value = false;
    await router.push(activityNotificationRoute(item));
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
      v-if="unreadCount"
      class="rounded-full bg-brand px-2 text-white"
    >{{ unreadCount }}</span>
  </button>
  <AppModal
    :open="open"
    title="Notifications"
    :busy="respond.isPending.value || markRead.isPending.value"
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
    <section
      class="mt-6"
      aria-labelledby="activity-notifications-title"
    >
      <h2
        id="activity-notifications-title"
        class="text-14 font-semibold mb-3"
      >
        Activity notifications
      </h2>
      <p
        v-if="activity.isPending.value"
        class="text-14 text-muted"
      >
        Loading activities…
      </p>
      <p
        v-else-if="activity.isError.value"
        class="text-14 text-danger"
      >
        Could not load activity notifications.
        <button
          class="underline focus-ring"
          @click="activity.refetch()"
        >
          Retry
        </button>
      </p>
      <p
        v-else-if="!activity.data.value?.unreadCount"
        class="text-14 text-muted"
      >
        No unread activity notifications.
      </p>
      <div
        v-else
        class="space-y-3"
      >
        <button
          v-for="item in activity.data.value?.items"
          :key="item.id"
          :disabled="markRead.isPending.value"
          class="block w-full min-w-0 text-left border border-line rounded-lg p-4 focus-ring hover:bg-paper [overflow-wrap:anywhere] disabled:opacity-50"
          @click="openActivity(item)"
        >
          <span class="block text-14 font-semibold">New activity</span>
          <span class="block mt-1 text-14">“{{ item.activity_title }}” was added to {{ item.project_name }}.</span>
          <time
            class="block mt-2 text-13 text-muted"
            :datetime="item.created_at"
          >{{ new Date(item.created_at).toLocaleDateString() }}</time>
        </button>
        <p
          v-if="(activity.data.value?.unreadCount ?? 0) > 50"
          class="text-13 text-muted"
        >
          Showing the newest 50. Open notifications to see older unread activities.
        </p>
      </div>
    </section>
    <p
      v-if="message"
      role="status"
      class="mt-3 text-14"
    >
      {{ message }}
    </p>
  </AppModal>
</template>

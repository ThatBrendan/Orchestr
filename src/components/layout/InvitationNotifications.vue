<script setup lang="ts">
import { computed, ref } from 'vue';
import { useQueryClient } from '@tanstack/vue-query';
import { qk } from '@/composables/keys';
import { useRouter } from 'vue-router';
import { notificationRoute, type InboxNotification } from '@/services/notifications';
import { useNotifications } from '@/composables/useNotifications';
import { toAppError } from '@/lib/errors';
import AppModal from '@/components/ui/AppModal.vue';
import AppButton from '@/components/ui/AppButton.vue';
import { presentLabel } from '@/lib/presentation';
const open = ref(false), message = ref('');
const router = useRouter(), client = useQueryClient();
const { pending, respond, inbox, count, markRead, markAllRead, unreadCount } = useNotifications();
const items = computed(() => inbox.data.value?.pages.flatMap(page => page.items) ?? []);
async function answer(token: string, action: 'accept' | 'decline') {
 message.value = '';
 try { const projectId = await respond.mutateAsync({ token, action });
  if (action === 'accept') { open.value = false; await router.push({ name: 'project.overview', params: { projectId } }); }
  else message.value = 'Invitation declined.';
 } catch (error) { message.value = toAppError(error).message; }
}
async function visit(item: InboxNotification) {
 message.value = '';
 try {
  await markRead.mutateAsync(item.id);
  await Promise.all([qk.project.root(item.project_id), qk.me.projects()].map(queryKey => client.invalidateQueries({ queryKey })));
  open.value = false; await router.push(notificationRoute(item));
 } catch (error) { message.value = toAppError(error).message; }
}
async function markAll() {
 message.value = '';
 try { const changed = await markAllRead.mutateAsync(); message.value = changed + ' notifications marked as read.'; }
 catch (error) { message.value = toAppError(error).message; }
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
    :busy="respond.isPending.value || markRead.isPending.value || markAllRead.isPending.value"
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
      class="mt-6 space-y-3"
      aria-labelledby="inbox-title"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2
          id="inbox-title"
          class="text-14 font-semibold"
        >
          Updates
        </h2>
        <AppButton
          variant="secondary"
          size="sm"
          :disabled="!count.data.value || markAllRead.isPending.value"
          @click="markAll"
        >
          Mark all as read
        </AppButton>
      </div>
      <p
        v-if="inbox.isPending.value"
        role="status"
      >
        Loading updates…
      </p>
      <p
        v-else-if="inbox.isError.value"
        role="alert"
      >
        Could not load updates. <button
          class="underline focus-ring"
          @click="inbox.refetch()"
        >
          Retry
        </button>
      </p>
      <p
        v-else-if="!items.length"
        class="text-14 text-muted"
      >
        No updates yet.
      </p>
      <button
        v-for="item in items"
        :key="item.id"
        :data-notification-id="item.id"
        :disabled="markRead.isPending.value"
        class="block w-full min-w-0 text-left border border-line rounded-lg p-4 focus-ring hover:bg-paper [overflow-wrap:anywhere]"
        @click="visit(item)"
      >
        <span
          v-if="!item.read_at"
          class="block text-12 font-semibold text-brand"
        >Unread</span>
        <span class="block font-semibold">{{ item.title }}</span>
        <span class="block text-14">{{ item.body }}</span>
        <time
          class="block mt-2 text-13 text-muted"
          :datetime="item.created_at"
        >{{ new Date(item.created_at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }) }}</time>
      </button>
      <AppButton
        v-if="inbox.hasNextPage.value"
        variant="secondary"
        :disabled="inbox.isFetchingNextPage.value"
        @click="inbox.fetchNextPage()"
      >
        Load older notifications
      </AppButton>
    </section>
    <p
      v-if="message"
      role="status"
      class="mt-4 text-14"
    >
      {{ message }}
    </p>
  </AppModal>
</template>

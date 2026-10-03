<script setup lang="ts">
import { ref } from "vue";
import { useQueryClient } from "@tanstack/vue-query";
import { qk } from "@/composables/keys";
import { useRouter } from "vue-router";
import { useMoney } from "@/composables/useMoney";
import { DateTime } from "luxon";
import { reimbursementNotificationRoute, type ReimbursementNotification, type PaymentAcknowledgementNotification, paymentNotificationRoute, type PaymentNotification, decisionNotificationRoute, type DecisionNotification, activityNotificationRoute, joinNotificationRoute, type JoinNotification, type ActivityNotification } from "@/services/notifications";
import { useNotifications } from "@/composables/useNotifications";
import { toAppError } from "@/lib/errors";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { presentLabel } from "@/lib/presentation";

const { format } = useMoney();
const open = ref(false);
const message = ref("");
const router = useRouter();
const client = useQueryClient();
const { pending, respond, activity, joins, decisions, payments, reimbursements, acknowledgements, markRead, unreadCount } = useNotifications();
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
async function openJoin(item: JoinNotification) {
  if (markRead.isPending.value) return;
  message.value = "";
  try { await markRead.mutateAsync(item.id);
    await Promise.all([qk.project.root(item.project_id), qk.me.projects()].map(queryKey => client.invalidateQueries({ queryKey })));
    open.value = false; await router.push(joinNotificationRoute(item)); }
  catch (error) { message.value = toAppError(error).message; }
}
async function openDecision(item: DecisionNotification) {
  if (markRead.isPending.value) return;
  message.value = "";
  try { await markRead.mutateAsync(item.id); open.value = false; await router.push(decisionNotificationRoute(item)); }
  catch (error) { message.value = toAppError(error).message; }
}
async function openPayment(item: PaymentNotification) {
  if (markRead.isPending.value) return;
  message.value = "";
  try { await markRead.mutateAsync(item.id); open.value = false; await router.push(paymentNotificationRoute(item)); }
  catch (error) { message.value = toAppError(error).message; }
}
async function openReimbursement(item: ReimbursementNotification | PaymentAcknowledgementNotification) {
  if (markRead.isPending.value) return;
  message.value = "";
  try { await markRead.mutateAsync(item.id); open.value = false; await router.push(reimbursementNotificationRoute(item)); }
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
    <section
      class="mt-6 space-y-3"
      aria-labelledby="join-notifications-title"
    >
      <h2
        id="join-notifications-title"
        class="text-14 font-semibold"
      >
        Project access
      </h2>
      <p
        v-if="joins.isPending.value"
        class="text-14 text-muted"
      >
        Loading access notifications…
      </p>
      <p
        v-else-if="joins.isError.value"
        class="text-14 text-danger"
      >
        Could not load access notifications. <button
          class="underline focus-ring"
          @click="joins.refetch()"
        >
          Retry
        </button>
      </p>
      <p
        v-else-if="!joins.data.value?.unreadCount"
        class="text-14 text-muted"
      >
        No unread access notifications.
      </p>
      <button
        v-for="item in joins.data.value?.items"
        :key="item.id"
        :disabled="markRead.isPending.value"
        class="block w-full min-w-0 text-left border border-line rounded-lg p-4 focus-ring hover:bg-paper [overflow-wrap:anywhere] disabled:opacity-50"
        @click="openJoin(item)"
      >
        <span class="block text-14 font-semibold">{{ item.kind === 'project_join_requested' ? 'New project access request' : "You're in" }}</span>
        <span class="block mt-1 text-14">{{ item.kind === 'project_join_requested' ? 'Someone requested access to ' + item.project_name + '.' : 'Your request to join ' + item.project_name + ' was approved.' }}</span>
      </button>
      <p
        v-if="(joins.data.value?.unreadCount ?? 0) > 50"
        class="text-13 text-muted"
      >
        Showing the newest 50. Open notifications to see older requests.
      </p>
    </section>
    <section
      class="mt-6 space-y-3"
      aria-labelledby="decision-notifications-title"
    >
      <h2
        id="decision-notifications-title"
        class="text-14 font-semibold"
      >
        Decisions
      </h2>
      <p
        v-if="decisions.isPending.value"
        class="text-14"
      >
        Loading decisions…
      </p>
      <p
        v-else-if="decisions.isError.value"
        class="text-14"
      >
        Could not load decision notifications. <button
          class="underline focus-ring"
          @click="decisions.refetch()"
        >
          Retry
        </button>
      </p>
      <p
        v-else-if="!decisions.data.value?.unreadCount"
        class="text-14 text-muted"
      >
        No unread decision notifications.
      </p>
      <button
        v-for="item in decisions.data.value?.items"
        :key="item.id"
        :disabled="markRead.isPending.value"
        class="block w-full text-left border border-line rounded-lg p-4 focus-ring [overflow-wrap:anywhere]"
        @click="openDecision(item)"
      >
        <span class="block font-semibold">{{ item.kind === 'decision_resolved' ? 'Decision resolved' : 'Voting closed' }}</span>
        <span class="block text-14">{{ item.decision_title }} — {{ item.kind === 'decision_resolved' ? item.selected_title + ' was selected.' : 'Ready to resolve.' }}</span>
      </button>
      <p
        v-if="(decisions.data.value?.unreadCount ?? 0) > 50"
        class="text-13"
      >
        Showing the newest 50. Open notifications to see older decisions.
      </p>
    </section>
    <section
      class="mt-6 space-y-3"
      aria-labelledby="payment-notifications-title"
    >
      <h2
        id="payment-notifications-title"
        class="text-14 font-semibold"
      >
        Payments
      </h2>
      <p
        v-if="payments.isPending.value"
        class="text-14"
      >
        Loading payments…
      </p>
      <p
        v-else-if="payments.isError.value"
        class="text-14"
      >
        Could not load payment notifications. <button
          class="underline focus-ring"
          @click="payments.refetch()"
        >
          Retry
        </button>
      </p>
      <p
        v-else-if="!payments.data.value?.unreadCount"
        class="text-14 text-muted"
      >
        No unread payment notifications.
      </p>
      <button
        v-for="item in payments.data.value?.items"
        :key="item.id"
        :disabled="markRead.isPending.value"
        class="block w-full text-left border border-line rounded-lg p-4 focus-ring [overflow-wrap:anywhere]"
        @click="openPayment(item)"
      >
        <span class="block font-semibold">{{ item.title }} — {{ item.outstanding_minor > 0 ? 'Payment reminder' : 'Paid' }}</span>
        <span class="block text-14">{{ item.outstanding_minor > 0 ? format(item.outstanding_minor, item.currency) + ' outstanding. Due ' + DateTime.fromISO(item.due_on).toFormat('d MMMM') + '.' : 'This scheduled payment has been paid.' }}</span>
      </button>
      <p
        v-if="(payments.data.value?.unreadCount ?? 0) > 50"
        class="text-13"
      >
        Showing the newest 50. Open notifications to see older payments.
      </p>
    </section>
    <section
      class="mt-6 space-y-3"
      aria-labelledby="reimbursement-notifications-title"
    >
      <h2
        id="reimbursement-notifications-title"
        class="text-14 font-semibold"
      >
        Reimbursements
      </h2>
      <p
        v-if="reimbursements.isPending.value"
        class="text-14"
      >
        Loading reimbursements…
      </p>
      <p
        v-else-if="reimbursements.isError.value"
        class="text-14"
      >
        Could not load reimbursements. <button
          class="underline focus-ring"
          @click="reimbursements.refetch()"
        >
          Retry
        </button>
      </p>
      <p
        v-else-if="!reimbursements.data.value?.unreadCount"
        class="text-14 text-muted"
      >
        No unread reimbursements.
      </p>
      <button
        v-for="item in reimbursements.data.value?.items"
        :key="item.id"
        :disabled="markRead.isPending.value"
        class="block w-full text-left border border-line rounded-lg p-4 focus-ring [overflow-wrap:anywhere]"
        @click="openReimbursement(item)"
      >
        <span class="block font-semibold">{{ item.needs_review ? 'Reimbursement needs review' : 'Reimbursement requested' }}</span>
        <span class="block text-14">{{ item.needs_review ? item.activity_title + ': the financial position has changed. Ask the payer to review this request.' : 'You owe ' + item.creditor_name + ' ' + format(item.amount_minor, item.currency) + ' for ' + item.activity_title + '.' }}</span>
      </button>
      <p
        v-if="(reimbursements.data.value?.unreadCount ?? 0) > 50"
        class="text-13"
      >
        Showing the newest 50. Open notifications to see older reimbursements.
      </p>
    </section>
    <section
      class="mt-6 space-y-3"
      aria-labelledby="acknowledgement-notifications-title"
    >
      <h2
        id="acknowledgement-notifications-title"
        class="text-14 font-semibold"
      >
        Payment updates
      </h2>
      <p
        v-if="acknowledgements.isPending.value"
        class="text-14"
      >
        Loading payment updates…
      </p>
      <p
        v-else-if="acknowledgements.isError.value"
        class="text-14"
      >
        Could not load acknowledgements. <button
          class="underline focus-ring"
          @click="acknowledgements.refetch()"
        >
          Retry
        </button>
      </p>
      <p
        v-else-if="!acknowledgements.data.value?.unreadCount"
        class="text-14 text-muted"
      >
        No unread acknowledgements.
      </p>
      <button
        v-for="item in acknowledgements.data.value?.items"
        :key="item.id"
        :disabled="markRead.isPending.value"
        class="block w-full text-left border border-line rounded-lg p-4 focus-ring [overflow-wrap:anywhere]"
        @click="openReimbursement(item)"
      >
        <span class="block font-semibold">{{ item.needs_review ? 'Reimbursement needs review' : item.kind==='reimbursement_payment_acknowledged' ? 'Payment marked as sent' : 'Payment status updated' }}</span>
        <span class="block text-14">{{ item.needs_review ? item.activity_title + ': the financial position has changed. The payment-sent history remains available.' : item.kind==='reimbursement_payment_acknowledged' ? item.debtor_name+" says they've paid "+format(item.amount_minor,item.currency)+' for '+item.activity_title+'. Awaiting confirmation.' : item.debtor_name+' withdrew their payment-sent acknowledgement for '+item.activity_title+'.' }}</span>
      </button>
      <p
        v-if="(acknowledgements.data.value?.unreadCount ?? 0) > 50"
        class="text-13"
      >
        Showing the newest 50. Open notifications to see older acknowledgements.
      </p>
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

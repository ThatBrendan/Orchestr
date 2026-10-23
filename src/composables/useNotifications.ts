import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useQuery, useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { useAuthStore } from "@/stores/auth";
import * as activityNotifications from "@/services/notifications";
import * as invitations from "@/services/invitations";
import { qk } from "./keys";

export function useProjectInvitations(projectId: MaybeRefOrGetter<string>, enabled: MaybeRefOrGetter<boolean>) {
  return useQuery({
    queryKey: computed(() => qk.project.invitations(toValue(projectId))),
    queryFn: () => invitations.listProjectInvitations(toValue(projectId)),
    enabled: computed(() => toValue(enabled)),
    refetchInterval: 30_000,
  });
}

export function useNotifications() {
  const auth = useAuthStore();
  const client = useQueryClient();
  const pending = useQuery({
    queryKey: computed(() => [...qk.me.notifications(), auth.userId, auth.email]),
    queryFn: invitations.listMyInvitations,
    enabled: computed(() => auth.isAuthenticated),
    refetchInterval: 30_000,
  });
  const inbox = useInfiniteQuery({
    queryKey: computed(() => [...qk.me.notifications(), 'inbox', auth.userId]),
    initialPageParam: undefined as activityNotifications.NotificationCursor | undefined,
    queryFn: ({ pageParam }) => activityNotifications.listNotificationInbox(pageParam),
    getNextPageParam: page => page.next,
    enabled: computed(() => auth.isAuthenticated), refetchInterval: 30_000,
  });
  const unread = useQuery({ queryKey: computed(() => [...qk.me.notifications(), 'unread-state', auth.userId]), queryFn: activityNotifications.notificationUnreadState, enabled: computed(() => auth.isAuthenticated), refetchInterval: 30_000 });
  const markAllRead = useMutation({ mutationFn: activityNotifications.markAllNotificationsRead, onSuccess: () => client.invalidateQueries({ queryKey: qk.me.notifications() }) });
  const markRead = useMutation({
    mutationFn: activityNotifications.markNotificationRead,
    onSuccess: () => client.invalidateQueries({ queryKey: qk.me.notifications() }),
  });
  const unreadUnavailable = computed(() => pending.isError.value || unread.isError.value);
  const hasUnread = computed(() => unreadUnavailable.value || pending.isPending.value || unread.isPending.value
    ? null : (pending.data.value?.length ?? 0) > 0 || unread.data.value === true);
  const respond = useMutation({
    mutationFn: ({ token, action }: { token: string; action: "accept" | "decline" }) =>
      action === "accept" ? invitations.acceptInvitation(token) : invitations.declineInvitation(token),
    onSuccess: (projectId) => Promise.all([
      qk.me.notifications(), qk.project.root(projectId), qk.me.projects(), qk.me.people(),
      qk.me.attention(), qk.me.calendarRoot(), ["invitation"],
    ].map((queryKey) => client.invalidateQueries({ queryKey }))),
  });
  return { pending, respond, inbox, unread, markRead, markAllRead, hasUnread, unreadUnavailable };
}

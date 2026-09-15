import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
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
  const activity = useQuery({
    queryKey: computed(() => [...qk.me.notifications(), "activities", auth.userId]),
    queryFn: activityNotifications.listActivityNotifications,
    enabled: computed(() => auth.isAuthenticated),
    refetchInterval: 30_000,
  });
  const markRead = useMutation({
    mutationFn: activityNotifications.markNotificationRead,
    onSuccess: () => client.invalidateQueries({ queryKey: qk.me.notifications() }),
  });
  const unreadCount = computed(() => (pending.data.value?.length ?? 0) + (activity.data.value?.unreadCount ?? 0));
  const respond = useMutation({
    mutationFn: ({ token, action }: { token: string; action: "accept" | "decline" }) =>
      action === "accept" ? invitations.acceptInvitation(token) : invitations.declineInvitation(token),
    onSuccess: (projectId) => Promise.all([
      qk.me.notifications(), qk.project.root(projectId), qk.me.projects(), qk.me.people(),
      qk.me.attention(), qk.me.calendarRoot(), ["invitation"],
    ].map((queryKey) => client.invalidateQueries({ queryKey }))),
  });
  return { pending, respond, activity, markRead, unreadCount };
}

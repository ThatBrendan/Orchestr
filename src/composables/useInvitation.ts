import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as invitesService from "@/services/invitations";

/** Invite-accept flow (docs/TECHNICAL_ARCHITECTURE.md §5). */
export function useInvitation(token: MaybeRefOrGetter<string>, opts: { enabled: MaybeRefOrGetter<boolean> }) {
  const client = useQueryClient();
  const preview = useQuery({
    queryKey: computed(() => qk.invitation(toValue(token))),
    queryFn: () => invitesService.getInvitation(toValue(token)),
    enabled: computed(() => toValue(opts.enabled)),
    retry: false,
  });

  const accept = useMutation({
    mutationFn: () => invitesService.acceptInvitation(toValue(token)),
    onSuccess: (projectId) => Promise.all([
      qk.me.notifications(), qk.invitation(toValue(token)), qk.project.root(projectId), qk.me.projects(),
      qk.me.people(), qk.me.attention(), qk.me.calendarRoot(),
    ].map((queryKey) => client.invalidateQueries({ queryKey }))),
  });

  const decline = useMutation({
    mutationFn: () => invitesService.declineInvitation(toValue(token)),
    onSuccess: (projectId) => Promise.all([
      qk.me.notifications(), qk.invitation(toValue(token)), qk.project.root(projectId),
    ].map((queryKey) => client.invalidateQueries({ queryKey }))),
  });
  return { preview, accept, decline };
}

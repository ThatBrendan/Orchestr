import { computed, type MaybeRefOrGetter, toValue } from "vue";
import { useQuery, useMutation } from "@tanstack/vue-query";
import * as invitesService from "@/services/invitations";

/** Invite-accept flow (docs/TECHNICAL_ARCHITECTURE.md §5). */
export function useInvitation(token: MaybeRefOrGetter<string>, opts: { enabled: MaybeRefOrGetter<boolean> }) {
  const preview = useQuery({
    queryKey: computed(() => ["invitation", toValue(token)]),
    queryFn: () => invitesService.getInvitation(toValue(token)),
    enabled: computed(() => toValue(opts.enabled)),
    retry: false,
  });

  const accept = useMutation({
    mutationFn: () => invitesService.acceptInvitation(toValue(token)),
  });

  return { preview, accept };
}

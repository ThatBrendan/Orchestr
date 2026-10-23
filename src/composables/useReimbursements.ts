import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { useQuery, useQueryClient } from '@tanstack/vue-query';
import { useAuthStore } from '@/stores/auth';
import * as service from '@/services/reimbursements';
import { invalidatePlanning } from './invalidation';
import { qk } from './keys';
export function useReimbursements(project: MaybeRefOrGetter<string>, activity?: MaybeRefOrGetter<string | undefined>) {
  const auth = useAuthStore();
  return useQuery({ queryKey: computed(() => ['reimbursements', toValue(project), toValue(activity), auth.userId]), queryFn: () => service.listReimbursements(toValue(project), toValue(activity)), refetchInterval: 30000 });
}
export function useRefreshReimbursements(project: string) {
  const client = useQueryClient();
  return () => invalidatePlanning(client, project, [['reimbursements', project], qk.me.notifications()]);
}

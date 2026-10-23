import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { useQuery, useQueryClient } from '@tanstack/vue-query';
import { useAuthStore } from '@/stores/auth';
import { getPaymentStatus } from '@/services/paymentAcknowledgements';
import { qk } from './keys';
export function usePaymentStatus(request: MaybeRefOrGetter<string>) {
  const auth = useAuthStore();
  return useQuery({ queryKey: computed(() => ['reimbursement-payment-status', auth.userId, toValue(request)]), queryFn: () => getPaymentStatus(toValue(request)), gcTime: 0, refetchInterval: 30000, refetchOnWindowFocus: true });
}
export function useRefreshPaymentStatus(project: string) {
  const client = useQueryClient();
  // A claim changes workflow only. Do not invalidate accounting/settlement caches.
  return () => Promise.all([
    ['reimbursement-payment-status'], ['reimbursements', project], ['reimbursement-payment-options'],
    qk.me.notifications(), qk.me.attention(), qk.project.health(project), qk.project.overview(project),
  ].map(queryKey => client.invalidateQueries({ queryKey })));
}

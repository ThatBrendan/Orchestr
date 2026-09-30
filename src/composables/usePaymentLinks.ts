import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { useQuery, useQueryClient } from '@tanstack/vue-query';
import { useAuthStore } from '@/stores/auth';
import * as service from '@/services/paymentLinks';
export function usePaymentLinks() {
  const auth = useAuthStore(), client = useQueryClient();
  const query = useQuery({ queryKey: computed(() => ['my-payment-links', auth.userId]), queryFn: service.listMyPaymentLinks, enabled: computed(() => auth.isAuthenticated), staleTime: 0, gcTime: 0 });
  const refresh = () => Promise.all([client.invalidateQueries({ queryKey: ['my-payment-links'] }), client.invalidateQueries({ queryKey: ['reimbursement-payment-options'] })]);
  return { query, refresh };
}
export function useReimbursementPaymentOptions(request: MaybeRefOrGetter<string>) {
  const auth = useAuthStore();
  return useQuery({ queryKey: computed(() => ['reimbursement-payment-options', auth.userId, toValue(request)]), queryFn: () => service.getReimbursementPaymentOptions(toValue(request)), enabled: computed(() => auth.isAuthenticated), staleTime: 0, gcTime: 0, refetchInterval: 30000, refetchOnWindowFocus: 'always' });
}

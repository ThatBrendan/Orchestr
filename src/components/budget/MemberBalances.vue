<script setup lang="ts">
import { useProjectSettlement } from "@/composables/useSettlement";
import { useMoney } from "@/composables/useMoney";
import { getSettlementPresentation } from "@/lib/presentation";
const props = defineProps<{ projectId: string; currency: string }>();
const query = useProjectSettlement(() => props.projectId);
const { format } = useMoney();
</script>
<template>
  <section class="mt-8 space-y-3">
    <h2 class="font-medium">
      Member balances
    </h2>
    <p v-if="query.isPending.value">
      Loading balances…
    </p>
    <p
      v-else-if="query.isError.value"
      role="alert"
    >
      Could not load balances. <button
        class="underline"
        @click="query.refetch()"
      >
        Retry
      </button>
    </p>
    <template v-else>
      <p class="text-14">
        Total remaining across members: {{ format(query.data.value?.totals?.remaining_minor ?? 0,currency) }}
      </p>
      <p
        v-if="!query.data.value?.members.length"
        class="text-13 text-muted"
      >
        Allocate Activity shares to see member balances.
      </p>
      <div
        v-else
        class="overflow-x-auto rounded-xl border border-line"
        role="region"
        tabindex="0"
        aria-label="Member balances"
      >
        <table class="w-full whitespace-nowrap text-14">
          <caption class="sr-only">
            Allocated shares and net settled payments by member
          </caption>
          <thead>
            <tr>
              <th
                v-for="label in ['Person','Share','Paid','Remaining','Status']"
                :key="label"
                scope="col"
                class="p-3 text-left"
              >
                {{ label }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in query.data.value?.members"
              :key="row.member_id"
              class="border-t border-line"
            >
              <th
                scope="row"
                class="max-w-[12rem] whitespace-normal [overflow-wrap:anywhere] p-3 text-left font-medium"
              >
                {{ row.display_name }}{{ row.member_status==='removed' ? ' (removed)' : '' }}
              </th>
              <td class="p-3">
                {{ format(row.allocated_minor,currency) }}
              </td><td class="p-3">
                {{ format(row.paid_minor,currency) }}
              </td>
              <td class="p-3">
                {{ format(Math.abs(row.remaining_minor),currency) }}{{ row.remaining_minor<0 ? ' credit' : '' }}
              </td>
              <td
                class="p-3"
              >
                <span
                  :class="{
                    'text-danger': getSettlementPresentation(row.paid_minor, row.remaining_minor).tone === 'danger',
                    'text-amber': getSettlementPresentation(row.paid_minor, row.remaining_minor).tone === 'amber',
                    'text-accent': getSettlementPresentation(row.paid_minor, row.remaining_minor).tone === 'accent',
                  }"
                >
                  {{ getSettlementPresentation(row.paid_minor, row.remaining_minor).label }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="text-13 text-muted">
        Paid is net of refunds. Cancelled Activity costs are excluded; payment history remains. Credits do not settle another person's share.
      </p>
    </template>
  </section>
</template>

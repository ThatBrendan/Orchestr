<script setup lang="ts">
import { ref } from "vue";
import { DateTime } from "luxon";
import { useQueryClient } from "@tanstack/vue-query";
import { useMemberSettlement } from "@/composables/useSettlement";
import { useProjectContext } from "@/composables/useProjectContext";
import { useMoney } from "@/composables/useMoney";
import { invalidatePlanning } from "@/composables/invalidation";
import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { Enums } from "@/types/database";
import AppButton from "@/components/ui/AppButton.vue";
const props = defineProps<{ id: string; projectId: string; currency: string; timezone: string; canEdit: boolean }>();
const query = useMemberSettlement(() => props.id);
const { context, isOrganizer } = useProjectContext();
const { format, toMinor, toMajor } = useMoney();
const client = useQueryClient();
const member = ref(""); const amount = ref(""); const paidNow = ref(true);
const type = ref<Enums<'payment_type'>>('full');
const date = ref(DateTime.now().setZone(props.timezone).toISODate()!);
const busy = ref(false); const error = ref("");
function open(id: string, remaining: number) { member.value=id; amount.value=String(toMajor(Math.max(remaining,0),props.currency)); error.value=""; type.value='full'; paidNow.value=true; date.value=DateTime.now().setZone(props.timezone).toISODate()!; }
async function save() {
 if (busy.value) return;
 busy.value=true; error.value="";
 try {
  const value=toMinor(amount.value,props.currency);
  if (value == null || value<=0 || !date.value) throw new Error('Enter a positive amount and a date.');
  const { error: e }=await supabase.rpc('record_member_payment',{p_commitment:props.id,p_member:member.value,p_amount:value,p_type:type.value,p_paid_now:paidNow.value,p_date:date.value});
  if(e) throw e;
  await Promise.all([client.invalidateQueries({queryKey:['settlement']}),client.invalidateQueries({queryKey:['commitment',props.id]}),invalidatePlanning(client,props.projectId,[['project',props.projectId,'budget','categories']])]);
  member.value="";
 } catch(e) {error.value=toAppError(e).message;} finally {busy.value=false;}
}
</script>
<template>
  <section class="mt-4 space-y-3">
    <h3 class="text-14 font-medium">
      Member settlement
    </h3>
    <p
      v-if="query.isPending.value"
      class="text-13"
    >
      Loading member payments…
    </p>
    <p
      v-else-if="query.isError.value"
      role="alert"
    >
      Could not load member payments. <button
        class="underline"
        @click="query.refetch()"
      >
        Retry
      </button>
    </p>
    <p
      v-else-if="!query.data.value?.length"
      class="text-13 text-muted"
    >
      No member shares allocated.
    </p>
    <div
      v-for="row in query.data.value"
      :key="row.member_id"
      class="rounded-lg border border-line p-3 text-13 space-y-2"
    >
      <p class="font-medium">
        {{ row.display_name }}{{ row.member_status === 'removed' ? ' (removed)' : '' }}
      </p>
      <p>Share {{ format(row.allocated_minor,currency) }} · Paid {{ format(row.paid_minor,currency) }} · {{ row.remaining_minor === 0 ? 'Settled' : `${format(Math.abs(row.remaining_minor),currency)} ${row.remaining_minor < 0 ? 'credit' : 'remaining'}` }}</p>
      <AppButton
        v-if="canEdit && row.member_status === 'active' && (isOrganizer || context?.memberId === row.member_id)"
        size="sm"
        variant="secondary"
        @click="open(row.member_id,row.remaining_minor)"
      >
        Record payment
      </AppButton>
      <form
        v-if="member === row.member_id"
        class="space-y-3"
        @submit.prevent="save"
      >
        <label class="block">Amount ({{ currency }})<input
          v-model="amount"
          inputmode="decimal"
          class="block w-full border border-line rounded p-2"
          :disabled="busy"
        ></label>
        <label class="block">Payment type<select
          v-model="type"
          class="block w-full border border-line rounded p-2"
          :disabled="busy"
        ><option value="deposit">Deposit</option><option value="balance">Balance</option><option value="full">Full payment</option><option value="installment">Installment</option><option value="refund">Refund</option></select></label>
        <label class="block">Timing<select
          v-model="paidNow"
          class="block w-full border border-line rounded p-2"
          :disabled="busy"
        ><option :value="true">Paid now</option><option :value="false">Pay later</option></select></label>
        <label class="block">{{ paidNow ? 'Paid date' : 'Due date' }}<input
          v-model="date"
          type="date"
          required
          class="block border border-line rounded p-2"
          :disabled="busy"
        ></label>
        <p
          v-if="error"
          role="alert"
          class="text-danger"
        >
          {{ error }}
        </p>
        <AppButton
          type="submit"
          size="sm"
          :loading="busy"
        >
          Record payment
        </AppButton>
        <AppButton
          type="button"
          size="sm"
          variant="ghost"
          :disabled="busy"
          @click="member=''"
        >
          Cancel
        </AppButton>
      </form>
    </div>
  </section>
</template>

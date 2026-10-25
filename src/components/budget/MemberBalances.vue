<script setup lang="ts">
import { useExecutionDialogFocus } from "@/composables/useExecutionDialogFocus";
import ReimbursementStatusLabel from "@/components/commitments/ReimbursementStatusLabel.vue";
import {computed,ref} from 'vue';
import {useQuery,useQueryClient} from '@tanstack/vue-query';
import {DateTime} from 'luxon';
import {useReimbursements} from '@/composables/useReimbursements';
import {useProjectSettlement} from '@/composables/useSettlement';
import {useProjectContext} from '@/composables/useProjectContext';
import {useMoney} from '@/composables/useMoney';
import {invalidatePlanning} from '@/composables/invalidation';
import {supabase} from '@/lib/supabase';
import {toAppError} from '@/lib/errors';
import AppAvatar from '@/components/ui/AppAvatar.vue';
import SkeletonBlock from '@/components/ui/SkeletonBlock.vue';
import ErrorState from '@/components/ui/ErrorState.vue';
import AppButton from '@/components/ui/AppButton.vue';
import AppModal from '@/components/ui/AppModal.vue';
const props=defineProps<{projectId:string;currency:string;itemId?:string}>();
const reimbursements=useReimbursements(()=>props.projectId);
function memberRequests(id:string){return (reimbursements.data.value??[]).filter(r=>(r.debtor_member_id===id||r.creditor_member_id===id)&&(!props.itemId||r.commitment_id===props.itemId));}
const query=useProjectSettlement(()=>props.projectId),client=useQueryClient();
const {project,isOrganizer}=useProjectContext();const {format,toMinor,toMajor}=useMoney();
const lines=useQuery({queryKey:computed(()=>['settlement','items',props.projectId]),queryFn:async()=>{const {data,error}=await supabase.from('v_item_member_balances').select('*').eq('project_id',props.projectId);if(error)throw toAppError(error);return data;}});
const history=useQuery({queryKey:computed(()=>['settlement','history',props.projectId]),queryFn:async()=>{const {data,error}=await supabase.from('payments').select('*').eq('project_id',props.projectId).not('settlement_group_id','is',null).eq('direction','outgoing').is('deleted_at',null);if(error)throw toAppError(error);return data;}});
const selected=ref<NonNullable<typeof lines.data.value>[number]|null>(null),payee=ref(''),amount=ref(''),date=ref(''),error=ref(''),busy=ref(false);
const canSettle=computed(()=>isOrganizer.value&&project.value?.status!=='archived');
const creditors=computed(()=>(lines.data.value??[]).filter(l=>l.commitment_id===selected.value?.commitment_id&&l.remaining_minor<0&&l.member_status==='active'));
function memberLines(id:string){return (lines.data.value??[]).filter(l=>l.member_id===id&&(!props.itemId||l.commitment_id===props.itemId));}
function balanceLabel(amount:number){return amount===0?'Settled':(amount>0?'Owes ':'Is owed ')+format(Math.abs(amount),props.currency);}
function memberBalance(id:string, total:number){return props.itemId ? memberLines(id)[0]?.remaining_minor ?? 0 : total;}
function areaGroups(id:string){const result=new Map<string,ReturnType<typeof memberLines>>();for(const line of memberLines(id)){const key=line.area_title??'Activities without a Category';result.set(key,[...(result.get(key)??[]),line]);}return [...result];}
function open(line:NonNullable<typeof selected.value>){selected.value=line;payee.value=creditors.value[0]?.member_id??'';amount.value=String(toMajor(Math.min(line.remaining_minor,-(creditors.value[0]?.remaining_minor??0)),props.currency));date.value=DateTime.now().setZone(project.value?.timezone??'UTC').toISODate()!;error.value='';}
async function refresh(){await Promise.all([client.invalidateQueries({queryKey:['settlement']}),client.invalidateQueries({queryKey:['reimbursement-payment-status']}),invalidatePlanning(client,props.projectId)]);}
async function save(){if(!selected.value||busy.value)return;busy.value=true;error.value='';try{const minor=toMinor(amount.value,props.currency);if(!minor||!payee.value||!date.value)throw new Error('Choose a person, amount and date.');const {error:e}=await supabase.rpc('record_item_settlement',{p_item:selected.value.commitment_id,p_from:selected.value.member_id,p_to:payee.value,p_amount:minor,p_date:date.value});if(e)throw e;await refresh();selected.value=null;}catch(e){error.value=toAppError(e).message;}finally{busy.value=false;}}
const cancelling=ref<string|null>(null);
async function cancel(){if(!cancelling.value)return;busy.value=true;error.value='';try{const {error:e}=await supabase.rpc('cancel_item_settlement',{p_group:cancelling.value});if(e)throw e;await refresh();cancelling.value=null;}catch(e){error.value=toAppError(e).message;}finally{busy.value=false;}}
const focusFallback = ref<HTMLElement | null>(null);
const restoreDialogFocus = useExecutionDialogFocus(computed(() => !!selected.value || !!cancelling.value), focusFallback);
</script>
<template>
  <section
    class="mt-6 space-y-3"
    aria-label="Balances"
  >
    <h2
      ref="focusFallback"
      tabindex="-1"
      class="text-section-heading focus-ring"
    >
      Balances
    </h2>
    <div
      v-if="query.isPending.value||lines.isPending.value"
      role="status"
      aria-label="Loading balances"
      class="space-y-2"
    >
      <SkeletonBlock
        v-for="i in 3"
        :key="i"
        height="80px"
      />
    </div>
    <ErrorState
      v-else-if="query.isError.value||lines.isError.value"
      :error="query.error.value||lines.error.value"
      :retry="()=>{query.refetch();lines.refetch();}"
    />
    <p
      v-else-if="!query.data.value?.members.length"
      class="text-meta text-muted"
    >
      Split an Activity cost to see what each person owes.
    </p>
    <template v-else>
      <p
        v-if="!itemId && query.data.value?.members.every(member => member.remaining_minor === 0)"
        class="text-sm text-success"
      >
        Everyone is settled.
      </p>
      <details
        v-for="member in query.data.value?.members.filter(m=>!itemId||memberLines(m.member_id).length)"
        :key="member.member_id"
        class="group rounded-xl border border-line bg-surface p-4"
      >
        <summary class="cursor-pointer focus-ring rounded-lg min-h-11 flex flex-wrap items-center gap-3">
          <AppAvatar
            :name="member.display_name"
            :size="32"
          />
          <span class="min-w-0 flex-1 [overflow-wrap:anywhere]">
            <span class="block text-card-heading font-semibold break-words">{{ member.display_name }}{{ member.member_status==='removed'?' (removed)':'' }}</span>
            <span
              class="block mt-1 text-sm tnum"
              :class="memberBalance(member.member_id, member.remaining_minor) === 0 ? 'text-success' : 'text-ink-soft'"
            >{{ balanceLabel(memberBalance(member.member_id, member.remaining_minor)) }}</span>
          </span>
          <span class="text-meta underline self-center"><span class="group-open:hidden">View details</span><span class="hidden group-open:inline">Hide details</span><span class="sr-only"> for {{ member.display_name }}</span></span>
        </summary>
        <div
          v-for="[area,rows] in areaGroups(member.member_id)"
          :key="area"
          class="mt-4 space-y-2"
        >
          <h3 class="text-sm font-medium break-words">
            {{ area }}
          </h3><div
            v-for="line in rows"
            :key="line.commitment_id"
            class="flex flex-wrap items-center justify-between gap-2 text-meta border-t border-line pt-2"
          >
            <RouterLink
              :to="{name:'project.commitments',params:{projectId},query:{commitment:line.commitment_id}}"
              class="min-w-0 min-h-11 inline-flex items-center text-brand focus-ring [overflow-wrap:anywhere]"
            >
              {{ line.item_title }}
            </RouterLink><span>{{ balanceLabel(line.remaining_minor) }}</span><AppButton
              v-if="canSettle&&line.member_status==='active'&&line.remaining_minor>0&&lines.data.value?.some(c=>c.commitment_id===line.commitment_id&&c.remaining_minor<0&&c.member_status==='active')"
              size="sm"
              variant="secondary"
              @click="open(line)"
            >
              Mark settled
            </AppButton>
          </div>
        </div>
        <section
          v-if="memberRequests(member.member_id).length"
          class="mt-4 space-y-2 text-meta"
          aria-label="Reimbursement requests"
        >
          <h3 class="font-medium">
            Reimbursements
          </h3>
          <RouterLink
            v-for="request in memberRequests(member.member_id)"
            :key="request.id"
            :to="{name:'project.commitments',params:{projectId},query:{commitment:request.commitment_id,section:'reimbursements'}}"
            class="block rounded-lg border border-line p-3 focus-ring [overflow-wrap:anywhere]"
          >
            <span class="block font-medium">{{ request.activity_title }}</span>
            <span>{{ request.status!=='open'||request.needs_review ? request.debtor_name+' → '+request.creditor_name : request.is_debtor ? 'You owe '+request.creditor_name : request.is_creditor ? request.debtor_name+' owes you' : request.debtor_name+' owes '+request.creditor_name }} · {{ format(request.amount_minor,currency) }}</span>
            <ReimbursementStatusLabel :request="request" />
          </RouterLink>
        </section>
      </details>
    </template>
    <p
      v-if="reimbursements.isError.value"
      role="alert"
      class="text-meta"
    >
      Could not load reimbursement details. <button
        class="underline focus-ring min-h-11 px-2"
        @click="reimbursements.refetch()"
      >
        Retry
      </button>
    </p>
    <details
      v-if="history.data.value?.some(r=>!itemId||r.commitment_id===itemId)"
      class="text-meta"
    >
      <summary class="cursor-pointer focus-ring rounded-lg min-h-11 py-3">
        Settlement history
      </summary><div
        v-for="row in history.data.value.filter(r=>!itemId||r.commitment_id===itemId)"
        :key="row.id"
        class="mt-3 flex flex-wrap gap-2"
      >
        <span>{{ lines.data.value?.find(l=>l.member_id===row.paid_by_member_id)?.display_name??'Former member' }} · {{ format(row.amount_minor,currency) }} · {{ row.status==='paid'?'Settled':'Cancelled' }} · {{ row.paid_on??new Date(row.created_at).toLocaleDateString() }}</span><AppButton
          v-if="canSettle&&row.status==='paid'"
          variant="ghost"
          size="sm"
          @click="cancelling=row.settlement_group_id;error=''"
        >
          Cancel settlement
        </AppButton>
      </div>
    </details>
    <ErrorState
      v-if="history.isError.value"
      :error="history.error.value"
      :retry="() => history.refetch()"
    />
    <AppModal
      :open="!!selected"
      title="Record settlement"
      :busy="busy"
      @after-close="restoreDialogFocus"
      @close="selected=null"
    >
      <form
        class="space-y-4"
        @submit.prevent="save"
      >
        <p>{{ selected?.display_name }} settles {{ selected?.item_title }}. The original expense stays unchanged.</p><label class="block text-sm">Paid to<select
          v-model="payee"
          required
          class="block w-full min-h-11 p-2 border border-line rounded-lg focus-ring"
        ><option
          v-for="person in creditors"
          :key="person.member_id"
          :value="person.member_id"
        >{{ person.display_name }}</option></select></label><label class="block text-sm">Amount<input
          v-model="amount"
          inputmode="decimal"
          required
          class="block w-full min-h-11 p-2 border border-line rounded-lg focus-ring"
        ></label><label class="block text-sm">Date<input
          v-model="date"
          type="date"
          required
          class="block w-full min-h-11 p-2 border border-line rounded-lg focus-ring"
        ></label><p
          v-if="error"
          role="alert"
          class="text-danger"
        >
          {{ error }}
        </p><AppButton
          type="submit"
          :loading="busy"
        >
          Record settlement
        </AppButton>
      </form>
    </AppModal>
    <AppModal
      :open="!!cancelling"
      title="Cancel settlement"
      :busy="busy"
      @after-close="restoreDialogFocus"
      @close="cancelling=null"
    >
      <p>Cancel both sides of this settlement? Its history will remain.</p><p
        v-if="error"
        role="alert"
        class="text-danger"
      >
        {{ error }}
      </p><AppButton
        class="mt-4"
        :loading="busy"
        @click="cancel"
      >
        Confirm cancellation
      </AppButton>
    </AppModal>
  </section>
</template>

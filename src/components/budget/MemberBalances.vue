<script setup lang="ts">
import {computed,ref} from 'vue';
import {useQuery,useQueryClient} from '@tanstack/vue-query';
import {DateTime} from 'luxon';
import {useProjectSettlement} from '@/composables/useSettlement';
import {useProjectContext} from '@/composables/useProjectContext';
import {useMoney} from '@/composables/useMoney';
import {invalidatePlanning} from '@/composables/invalidation';
import {supabase} from '@/lib/supabase';
import {toAppError} from '@/lib/errors';
import AppButton from '@/components/ui/AppButton.vue';
import AppModal from '@/components/ui/AppModal.vue';
const props=defineProps<{projectId:string;currency:string;itemId?:string}>();
const query=useProjectSettlement(()=>props.projectId),client=useQueryClient();
const {project,isOrganizer}=useProjectContext();const {format,toMinor,toMajor}=useMoney();
const lines=useQuery({queryKey:computed(()=>['settlement','items',props.projectId]),queryFn:async()=>{const {data,error}=await supabase.from('v_item_member_balances').select('*').eq('project_id',props.projectId);if(error)throw toAppError(error);return data;}});
const history=useQuery({queryKey:computed(()=>['settlement','history',props.projectId]),queryFn:async()=>{const {data,error}=await supabase.from('payments').select('*').eq('project_id',props.projectId).not('settlement_group_id','is',null).eq('direction','outgoing').is('deleted_at',null);if(error)throw toAppError(error);return data;}});
const selected=ref<NonNullable<typeof lines.data.value>[number]|null>(null),payee=ref(''),amount=ref(''),date=ref(''),error=ref(''),busy=ref(false);
const canSettle=computed(()=>isOrganizer.value&&project.value?.status!=='archived');
const creditors=computed(()=>(lines.data.value??[]).filter(l=>l.commitment_id===selected.value?.commitment_id&&l.remaining_minor<0&&l.member_status==='active'));
function memberLines(id:string){return (lines.data.value??[]).filter(l=>l.member_id===id&&(!props.itemId||l.commitment_id===props.itemId));}
function areaGroups(id:string){const result=new Map<string,ReturnType<typeof memberLines>>();for(const line of memberLines(id)){const key=line.area_title??'Activities without a Category';result.set(key,[...(result.get(key)??[]),line]);}return [...result];}
function open(line:NonNullable<typeof selected.value>){selected.value=line;payee.value=creditors.value[0]?.member_id??'';amount.value=String(toMajor(Math.min(line.remaining_minor,-(creditors.value[0]?.remaining_minor??0)),props.currency));date.value=DateTime.now().setZone(project.value?.timezone??'UTC').toISODate()!;error.value='';}
async function refresh(){await Promise.all([client.invalidateQueries({queryKey:['settlement']}),invalidatePlanning(client,props.projectId)]);}
async function save(){if(!selected.value||busy.value)return;busy.value=true;error.value='';try{const minor=toMinor(amount.value,props.currency);if(!minor||!payee.value||!date.value)throw new Error('Choose a person, amount and date.');const {error:e}=await supabase.rpc('record_item_settlement',{p_item:selected.value.commitment_id,p_from:selected.value.member_id,p_to:payee.value,p_amount:minor,p_date:date.value});if(e)throw e;await refresh();selected.value=null;}catch(e){error.value=toAppError(e).message;}finally{busy.value=false;}}
const cancelling=ref<string|null>(null);
async function cancel(){if(!cancelling.value)return;busy.value=true;error.value='';try{const {error:e}=await supabase.rpc('cancel_item_settlement',{p_group:cancelling.value});if(e)throw e;await refresh();cancelling.value=null;}catch(e){error.value=toAppError(e).message;}finally{busy.value=false;}}
</script>
<template>
  <section
    class="mt-6 space-y-3"
    aria-label="Balances"
  >
    <h2 class="font-display text-lg font-semibold">
      Balances
    </h2>
    <p v-if="query.isPending.value||lines.isPending.value">
      Loading balances…
    </p>
    <p
      v-else-if="query.isError.value||lines.isError.value"
      role="alert"
    >
      Could not load balances. <button
        class="underline"
        @click="()=>{query.refetch();lines.refetch();}"
      >
        Retry
      </button>
    </p>
    <p
      v-else-if="!query.data.value?.members.length"
      class="text-13 text-muted"
    >
      Split an Activity cost to see what each person owes.
    </p>
    <template v-else>
      <details
        v-for="member in query.data.value?.members.filter(m=>!itemId||memberLines(m.member_id).length)"
        :key="member.member_id"
        class="rounded-xl border border-line bg-surface p-4"
      >
        <summary class="cursor-pointer focus-ring flex flex-wrap justify-between gap-2">
          <span class="font-medium break-words">{{ member.display_name }}{{ member.member_status==='removed'?' (removed)':'' }}</span><span
            v-if="!itemId"
            class="text-14"
          >{{ member.remaining_minor===0?'Settled':format(Math.abs(member.remaining_minor),currency)+(member.remaining_minor>0?' outstanding':' to receive') }}</span>
        </summary>
        <div
          v-for="[area,rows] in areaGroups(member.member_id)"
          :key="area"
          class="mt-4 space-y-2"
        >
          <h3 class="text-14 font-medium break-words">
            {{ area }}
          </h3><div
            v-for="line in rows"
            :key="line.commitment_id"
            class="flex flex-wrap items-center justify-between gap-2 text-13 border-t border-line pt-2"
          >
            <span class="min-w-0 break-words">{{ line.item_title }}</span><span>{{ line.remaining_minor===0?'Settled':format(Math.abs(line.remaining_minor),currency)+(line.remaining_minor<0?' to receive':' outstanding') }}</span><AppButton
              v-if="canSettle&&line.member_status==='active'&&line.remaining_minor>0&&lines.data.value?.some(c=>c.commitment_id===line.commitment_id&&c.remaining_minor<0&&c.member_status==='active')"
              size="sm"
              variant="secondary"
              @click="open(line)"
            >
              Mark settled
            </AppButton>
          </div>
        </div>
      </details>
    </template>
    <details
      v-if="history.data.value?.length"
      class="text-13"
    >
      <summary class="cursor-pointer focus-ring">
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
    <AppModal
      :open="!!selected"
      title="Record settlement"
      :busy="busy"
      @close="selected=null"
    >
      <form
        class="space-y-4"
        @submit.prevent="save"
      >
        <p>{{ selected?.display_name }} settles {{ selected?.item_title }}. The original expense stays unchanged.</p><label class="block text-14">Paid to<select
          v-model="payee"
          required
          class="block w-full p-2 border border-line rounded-lg"
        ><option
          v-for="person in creditors"
          :key="person.member_id"
          :value="person.member_id"
        >{{ person.display_name }}</option></select></label><label class="block text-14">Amount<input
          v-model="amount"
          inputmode="decimal"
          required
          class="block w-full p-2 border border-line rounded-lg"
        ></label><label class="block text-14">Date<input
          v-model="date"
          type="date"
          required
          class="block w-full p-2 border border-line rounded-lg"
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

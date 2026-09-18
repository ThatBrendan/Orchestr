<script setup lang="ts">
import {ref} from 'vue';
import {useQueryClient} from '@tanstack/vue-query';
import {useAreas} from '@/composables/useItems';
import {invalidatePlanning} from '@/composables/invalidation';
import {updateTask} from '@/services/tasks';
import {toAppError} from '@/lib/errors';
import type {Item} from '@/services/items';
import type {Commitment} from '@/services/commitments';
import type {MemberDirectoryEntry} from '@/types/derived';
import AppModal from '@/components/ui/AppModal.vue';
import AppButton from '@/components/ui/AppButton.vue';
import TasksPanel from './TasksPanel.vue';
const props=defineProps<{item:Item;projectId:string;timezone:string;currency:string;members:MemberDirectoryEntry[];commitments:Commitment[];canEdit:boolean}>();
const emit=defineEmits<{close:[];editLedger:[id:string]}>();
const areas=useAreas(()=>props.projectId),client=useQueryClient();
const title=ref(props.item.title),notes=ref(props.item.notes??''),area=ref(props.item.area_id??''),type=ref(props.item.item_type),date=ref(props.item.item_date?.slice(0,10)??'');
const busy=ref(false),error=ref('');
async function save(){busy.value=true;error.value='';try{await updateTask(props.item.id,{title:title.value,notes:notes.value||null,area_id:area.value||null,item_type:type.value,due_on:date.value||null});await invalidatePlanning(client,props.projectId,[['project',props.projectId,'tasks']]);emit('close');}catch(e){error.value=toAppError(e).message;}finally{busy.value=false;}}
</script>
<template>
  <AppModal
    :open="true"
    :title="item.title"
    :busy="busy"
    @close="emit('close')"
  >
    <form
      v-if="canEdit"
      class="space-y-3"
      @submit.prevent="save"
    >
      <label class="block text-14">Activity title<input
        v-model="title"
        required
        class="block w-full border border-line rounded-lg p-2"
      ></label>
      <label class="block text-14">Activity type<select
        v-model="type"
        class="block w-full border border-line rounded-lg p-2"
      ><option
        v-for="t in ['Task','Event','Booking','Purchase','Other']"
        :key="t"
        :value="t.toLowerCase()"
      >{{ t }}</option></select></label>
      <label class="block text-14">Category<select
        v-model="area"
        class="block w-full border border-line rounded-lg p-2"
      ><option value="">No Category</option><option
        v-for="a in areas.data.value"
        :key="a.id"
        :value="a.id"
      >{{ a.title }}</option></select></label>
      <label class="block text-14">Due date<input
        v-model="date"
        type="date"
        class="block w-full border border-line rounded-lg p-2"
      ></label>
      <label class="block text-14">Notes<textarea
        v-model="notes"
        class="block w-full border border-line rounded-lg p-2"
      /></label>
      <p
        v-if="error"
        role="alert"
        class="text-danger"
      >
        {{ error }}
      </p><AppButton
        type="submit"
        :loading="busy"
      >
        Save activity
      </AppButton>
      <AppButton
        v-if="item.financial_id"
        type="button"
        variant="secondary"
        @click="emit('editLedger',item.financial_id)"
      >
        Edit cost and split
      </AppButton>
    </form>
    <p
      v-else
      class="text-14 whitespace-pre-wrap"
    >
      {{ item.notes }}
    </p>
    <TasksPanel
      :project-id="projectId"
      :timezone="timezone"
      :can-edit="canEdit"
      :members="members"
      :commitments="commitments"
      :only-id="item.id"
      :financial-id="item.financial_id"
    />
  </AppModal>
</template>

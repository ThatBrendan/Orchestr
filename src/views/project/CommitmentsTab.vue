<script setup lang="ts">
import {computed,ref,watch} from 'vue';
import {useRoute,useRouter} from 'vue-router';
import {useQueryClient} from '@tanstack/vue-query';
import {useCommitments} from '@/composables/useCommitments';
import {useAreas,useItems} from '@/composables/useItems';
import {useMemberDirectory} from '@/composables/useProject';
import {useProjectContext} from '@/composables/useProjectContext';
import {useMoney} from '@/composables/useMoney';
import {useToast} from '@/composables/useToast';
import {toAppError} from '@/lib/errors';
import {itemStatusLabel,itemTypeLabel} from '@/lib/itemPresentation';
import {deleteArea,saveArea,type Item} from '@/services/items';
import type {Commitment} from '@/services/commitments';
import AppButton from '@/components/ui/AppButton.vue';
import AppModal from '@/components/ui/AppModal.vue';
import ErrorState from '@/components/ui/ErrorState.vue';
import AppConfirmDialog from '@/components/ui/AppConfirmDialog.vue';
import StatusBadge from '@/components/ui/StatusBadge.vue';
import CommitmentFormDialog from '@/components/commitments/CommitmentFormDialog.vue';
import CommitmentDetailDialog from '@/components/commitments/CommitmentDetailDialog.vue';
import LegacyItemDialog from '@/components/tasks/LegacyItemDialog.vue';
const route=useRoute(),router=useRouter(),client=useQueryClient(),toast=useToast();
const projectId=computed(()=>String(route.params.projectId));
const {project,allowed,context}=useProjectContext();
const {commitments}=useCommitments(projectId);
const areas=useAreas(projectId),items=useItems(projectId);
const {members}=useMemberDirectory(projectId);const {format}=useMoney();
const currency=computed(()=>project.value?.currency??'GBP'),timezone=computed(()=>project.value?.timezone??'UTC');
const canEdit=computed(()=>allowed('commitment.edit')&&project.value?.status!=='archived');
const selected=computed(()=>typeof route.query.area==='string'?route.query.area:null);
const selectedArea=computed(()=>areas.data.value?.find(a=>a.id===selected.value));
const visibleItems=computed(()=>(items.data.value??[]).filter(i=>selected.value==='unassigned'?i.area_id==null:i.area_id===selected.value));
const groupedItems=computed(()=>{
 const groups=new Map<string,Item[]>();
 for(const area of areas.data.value??[]) groups.set(area.title,[]);
 for(const item of items.data.value??[]){
  const key=areas.data.value?.find(area=>area.id===item.area_id)?.title??'Activities without a Category';
  groups.set(key,[...(groups.get(key)??[]),item]);
 }
 return [...groups];
});
const detail=computed(()=>commitments.value.find(c=>c.id===route.query.commitment));
const legacy=computed(()=>items.data.value?.find(i=>i.id===route.query.item&&i.source==='task'));
const formOpen=ref(false),editing=ref<Commitment|null>(null);
const areaOpen=ref(false),areaTitle=ref(''),areaNotes=ref(''),areaError=ref(''),saving=ref(false),editingAreaId=ref<string>();
const deleteCategoryOpen=ref(false);
function selectArea(id:string|null){void router.replace({query:id?{area:id}:{}});}
function openItem(item:Item){void router.replace({query:{...route.query,...(item.source==='task'?{item:item.id}:{commitment:item.id})}});}
function closeDetail(){const q={...route.query};delete q.commitment;delete q.item;delete q.occurrence;void router.replace({query:q});}
function createItem(){editing.value=null;formOpen.value=true;}
function editItem(){editing.value=detail.value??null;closeDetail();formOpen.value=true;}
function editLedger(id:string){editing.value=commitments.value.find(c=>c.id===id)??null;closeDetail();formOpen.value=true;}
function canDelete(c:Commitment){return canEdit.value&&(context.value?.role==='organizer'||c.created_by===context.value?.memberId||c.owner_member_id===context.value?.memberId);}
function openArea(edit=false){editingAreaId.value=edit?selectedArea.value?.id:undefined;areaTitle.value=edit?selectedArea.value?.title??'':'';areaNotes.value=edit?selectedArea.value?.notes??'':'';areaError.value='';areaOpen.value=true;}
async function submitArea(){if(saving.value)return;saving.value=true;areaError.value='';try{const area=await saveArea(projectId.value,areaTitle.value.trim(),areaNotes.value,editingAreaId.value);await client.invalidateQueries({queryKey:['project',projectId.value,'areas']});areaOpen.value=false;selectArea(area.id);toast.success('Category saved.');}catch(e){areaError.value=toAppError(e).message;}finally{saving.value=false;}}
async function removeCategory(){if(!selectedArea.value||saving.value)return;saving.value=true;try{await deleteArea(selectedArea.value.id);await client.invalidateQueries({queryKey:['project',projectId.value,'areas']});deleteCategoryOpen.value=false;selectArea(null);toast.success('Category deleted.');}catch(e){toast.error(toAppError(e).message);}finally{saving.value=false;}}
watch(()=>items.data.value,()=>{if(!items.isPending.value&&route.query.item&&!legacy.value)closeDetail();});
</script>
<template>
  <div class="space-y-5 fade-in">
    <div class="flex flex-wrap justify-between items-center gap-3">
      <div>
        <AppButton
          v-if="selected"
          variant="ghost"
          size="sm"
          class="mb-2"
          @click="selectArea(null)"
        >
          ← Back to Activities
        </AppButton>
        <h2 class="font-display text-xl font-semibold">
          {{ selectedArea?.title ?? (selected ? 'Activities without a Category' : 'Activities') }}
        </h2>
      </div>
      <div
        v-if="canEdit"
        class="flex flex-wrap gap-2"
      >
        <AppButton
          v-if="selectedArea"
          variant="secondary"
          size="sm"
          @click="openArea(true)"
        >
          Edit category
        </AppButton><AppButton
          v-if="selectedArea"
          variant="ghost"
          size="sm"
          class="!text-danger"
          @click="deleteCategoryOpen=true"
        >
          Delete category
        </AppButton><AppButton
          v-if="!selected"
          size="sm"
          @click="openArea()"
        >
          New category
        </AppButton>
      </div>
    </div>
    <p
      v-if="selectedArea?.notes"
      class="text-14 whitespace-pre-wrap"
    >
      {{ selectedArea?.notes }}
    </p>
    <p v-if="areas.isPending.value||items.isPending.value">
      Loading categories and activities…
    </p>
    <ErrorState
      v-else-if="areas.isError.value||items.isError.value"
      :error="areas.error.value||items.error.value"
      :retry="()=>{areas.refetch();items.refetch();}"
    />
    <template v-else>
      <div
        v-if="!selected"
        class="grid gap-3 sm:grid-cols-2"
      >
        <section
          v-for="[category,rows] in groupedItems"
          :key="category"
          class="rounded-xl border border-line bg-surface"
        >
          <button
            class="flex w-full items-center justify-between gap-3 border-b border-line px-4 py-3 text-left focus-ring"
            @click="category === 'Activities without a Category' ? selectArea('unassigned') : selectArea(areas.data.value?.find(area => area.title === category)?.id ?? null)"
          >
            <span class="font-medium break-words">{{ category }}</span>
            <span class="text-13 text-muted">{{ rows.length }} {{ rows.length === 1 ? 'activity' : 'activities' }}</span>
          </button>
          <button
            v-for="activity in rows"
            :key="activity.source + activity.id"
            class="flex w-full flex-wrap items-center justify-between gap-3 border-b border-line px-4 py-3 text-left last:border-b-0 focus-ring"
            @click="openItem(activity)"
          >
            <span class="min-w-0 flex-1">
              <span class="block font-medium break-words">{{ activity.title }}</span>
              <span class="block text-13 text-muted">{{ itemTypeLabel(activity.item_type) }} · {{ members.find(m=>m.member_id===activity.assignee_member_id)?.display_name??'Unassigned' }}<template v-if="activity.item_date"> · {{ new Date(activity.item_date).toLocaleDateString(undefined,{timeZone:timezone}) }}</template></span>
              <span class="mt-2 inline-flex"><StatusBadge :label="itemStatusLabel(activity)" :tone="activity.status === 'completed' ? 'success' : 'amber'" /></span>
            </span>
            <span class="text-14">{{ activity.cost_minor==null?'No cost':format(activity.cost_minor,currency) }}</span>
          </button>
        </section>
        <p
          v-if="!groupedItems.length"
          class="text-muted"
        >
          Add an activity to get started.
        </p>
      </div>
      <div
        v-else
        class="rounded-xl border border-line bg-surface divide-y divide-line"
      >
        <div class="flex justify-end border-b border-line p-3">
          <AppButton
            v-if="canEdit && selectedArea"
            size="sm"
            @click="createItem"
          >
            Add activity
          </AppButton>
        </div>
        <p
          v-if="!visibleItems.length"
          class="p-5 text-muted"
        >
          No activities in this Category yet.
        </p>
        <button
          v-for="item in visibleItems"
          :key="item.source+item.id"
          class="w-full text-left p-4 focus-ring flex flex-wrap gap-3 justify-between"
          @click="openItem(item)"
        >
          <span class="min-w-0 flex-1">
            <span class="block font-medium break-words">{{ item.title }}</span>
            <span class="block text-13 text-muted mt-1">{{ itemTypeLabel(item.item_type) }} · {{ members.find(m=>m.member_id===item.assignee_member_id)?.display_name??'Unassigned' }}<template v-if="item.item_date"> · {{ new Date(item.item_date).toLocaleDateString(undefined,{timeZone:timezone}) }}</template></span>
            <span class="mt-2 inline-flex"> <StatusBadge :label="itemStatusLabel(item)" :tone="item.status === 'completed' ? 'success' : 'amber'" /> </span>
          </span>
          <span class="text-14">{{ item.cost_minor==null?'No cost':format(item.cost_minor,currency) }}</span>
        </button>
      </div>
    </template>
    <AppModal
      :open="areaOpen"
      :busy="saving"
      :title="editingAreaId?'Edit category':'New category'"
      @close="areaOpen=false"
    >
      <form
        class="space-y-4"
        @submit.prevent="submitArea"
      >
        <label class="block text-14">Category name *<input
          v-model="areaTitle"
          required
          maxlength="120"
          class="block w-full mt-1 border border-line rounded-lg p-3 focus-ring"
        ></label><label class="block text-14">Notes<textarea
          v-model="areaNotes"
          class="block w-full mt-1 border border-line rounded-lg p-3 focus-ring"
        /></label><p
          v-if="areaError"
          role="alert"
          class="text-danger"
        >
          {{ areaError }}
        </p><AppButton
          type="submit"
          :loading="saving"
        >
          Save category
        </AppButton>
      </form>
    </AppModal>
    <AppConfirmDialog
      :open="deleteCategoryOpen"
      title="Delete category"
      message="Categories can only be deleted when they have no activities. Existing activities are never deleted."
      confirm-label="Delete category"
      danger
      :loading="saving"
      @close="deleteCategoryOpen=false"
      @confirm="removeCategory"
    />
    <CommitmentFormDialog
      :open="formOpen"
      :project-id="projectId"
      :currency="currency"
      :timezone="timezone"
      :project-profile="project?.profile??'blank'"
      :member-options="members"
      :commitment="editing"
      :default-area-id="selectedArea?.id"
      @close="formOpen=false"
    />
    <CommitmentDetailDialog
      v-if="detail"
      :key="detail.id"
      :open="true"
      :project-id="projectId"
      :currency="currency"
      :timezone="timezone"
      :commitment="detail"
      :members="members"
      :can-edit="canEdit"
      :can-edit-payments="canEdit"
      :can-delete="canDelete(detail)"
      :occurrence-date="typeof route.query.occurrence==='string'?route.query.occurrence:undefined"
      @close="closeDetail"
      @edit="editItem"
    />
    <LegacyItemDialog
      v-if="legacy"
      :key="legacy.id"
      :item="legacy"
      :project-id="projectId"
      :timezone="timezone"
      :currency="currency"
      :members="members"
      :commitments="commitments"
      :can-edit="canEdit"
      @close="closeDetail"
      @edit-ledger="editLedger"
    />
  </div>
</template>

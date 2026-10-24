<script setup lang="ts">
import {computed, ref, watch, onMounted} from 'vue';
import {useRoute} from 'vue-router';
import {useProjectContext} from '@/composables/useProjectContext';
import {useQuery} from '@tanstack/vue-query';
import {supabase} from '@/lib/supabase';
import {toAppError} from '@/lib/errors';
import {useProjectHealth,useUpcoming,useProjectFinancials,useMemberDirectory} from '@/composables/useProject';
import {useMoney} from '@/composables/useMoney';
import { paginateList } from '@/lib/pagination';
import SectionHeading from '@/components/ui/SectionHeading.vue';
import SkeletonBlock from '@/components/ui/SkeletonBlock.vue';
import ErrorState from '@/components/ui/ErrorState.vue';
import AppButton from '@/components/ui/AppButton.vue';
import AppIcon from '@/components/ui/AppIcon.vue';
import AppAvatar from '@/components/ui/AppAvatar.vue';
import { attentionDestination } from '@/lib/attentionDestination';
import AttentionRow from '@/components/health/AttentionRow.vue';
import UpcomingList from '@/components/timeline/UpcomingList.vue';

const overviewTitle = ref<HTMLElement | null>(null);
onMounted(() => overviewTitle.value?.focus({ preventScroll: true }));
const route=useRoute(),projectId=computed(()=>String(route.params.projectId));
const {project,allowed}=useProjectContext(),{format}=useMoney();
const planningEmpty=useQuery({queryKey:computed(()=>['project',projectId.value,'planning-empty']),staleTime:0,queryFn:async()=>{
 const results=await Promise.all([
  supabase.from('project_areas').select('id').eq('project_id',projectId.value).limit(1),
  supabase.from('v_project_items').select('id').eq('project_id',projectId.value).limit(1),
 ]);
 for(const result of results)if(result.error)throw toAppError(result.error);
 return results.every(result=>result.data?.length===0);
}});
const needsFirstCategory=computed(()=>planningEmpty.data.value===true);
const financials=useProjectFinancials(projectId),health=useProjectHealth(projectId),upcoming=useUpcoming(projectId);
const directory = useMemberDirectory(projectId);
const roster = computed(() => directory.members.value.filter(member => member.status !== 'removed'));
const invited = computed(() => roster.value.filter(member => member.status === 'invited').length);
const currency=computed(()=>project.value?.currency??'GBP');
const page = ref(1);
const perPage = 5;
const attentionPage = computed(() => {
  const items = health.needsAttention.value ?? [];
  return paginateList(items, page.value, perPage);
});
watch(() => health.needsAttention.value.length, () => {
  const total = Math.max(1, Math.ceil((health.needsAttention.value?.length ?? 0) / perPage));
  if (page.value > total) page.value = total;
  if ((health.needsAttention.value?.length ?? 0) <= perPage) page.value = 1;
});
</script>
<template>
  <div class="space-y-8 fade-in">
    <section aria-label="Needs attention">
      <h2
        ref="overviewTitle"
        tabindex="-1"
        class="text-section-heading text-ink-soft focus:outline-none"
      >
        Needs attention
      </h2>
      <div
        v-if="health.isPending.value"
        class="mt-3 space-y-2"
      >
        <SkeletonBlock
          v-for="i in 2"
          :key="i"
          height="80px"
          rounded="0.75rem"
        />
      </div>
      <ErrorState
        v-else-if="health.isError.value"
        class="mt-3"
        :error="health.error.value"
        :retry="() => health.refetch()"
      />
      <p
        v-else-if="!health.needsAttention.value.length"
        class="mt-3 flex items-center gap-2 text-sm text-ink-soft"
      >
        <AppIcon
          name="checkCircle"
          :size="18"
          class="shrink-0 text-success"
        />All clear — nothing needs attention on this project.
      </p>
      <template v-else>
        <div class="mt-3 rounded-xl border border-line divide-y divide-line bg-surface">
          <AttentionRow
            v-for="(f, i) in attentionPage.items"
            :key="f.code + (f.subject_id ?? '') + i"
            :finding="f"
            :to="attentionDestination(projectId, f).to"
            :destination-label="attentionDestination(projectId, f).label"
          />
        </div>
        <div
          v-if="health.needsAttention.value.length > perPage"
          class="mt-3 flex items-center justify-between gap-3 text-meta text-muted"
        >
          <AppButton
            variant="secondary"
            size="sm"
            :disabled="!attentionPage.canGoPrevious"
            aria-label="Previous needs attention page"
            @click="page = Math.max(1, page - 1)"
          >
            Previous
          </AppButton>
          <span aria-live="polite">Page {{ attentionPage.page }} of {{ attentionPage.totalPages }}</span>
          <AppButton
            variant="secondary"
            size="sm"
            :disabled="!attentionPage.canGoNext"
            aria-label="Next needs attention page"
            @click="page = Math.min(attentionPage.totalPages, page + 1)"
          >
            Next
          </AppButton>
        </div>
      </template>
    </section>

    <SkeletonBlock
      v-if="planningEmpty.isPending.value"
      height="120px"
      rounded="0.75rem"
    />
    <ErrorState
      v-else-if="planningEmpty.isError.value"
      :error="planningEmpty.error.value"
      :retry="() => planningEmpty.refetch()"
    />
    <section
      v-else-if="needsFirstCategory"
      aria-label="Get started"
      class="rounded-xl border border-line bg-surface p-5 space-y-3"
    >
      <h2 class="text-section-heading">
        Start planning your project
      </h2>
      <p class="text-sm text-ink-soft">
        Group your activities in a Category, then add what needs doing.
      </p>
      <AppButton
        v-if="allowed('commitment.edit') && project?.status !== 'archived'"
        :to="{name:'project.commitments',params:{projectId},query:{createCategory:'1'}}"
      >
        Create your first category
      </AppButton>
      <p
        v-else
        class="text-sm text-muted"
      >
        Your project team hasn't added any activities yet.
      </p>
    </section>

    <section
      v-if="!needsFirstCategory || upcoming.events.value.length || upcoming.isError.value"
      aria-label="Upcoming"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div>
          <SectionHeading label="Upcoming" /><p class="mt-1 text-meta text-muted">
            The next two weeks
          </p>
        </div>
        <AppButton
          variant="ghost"
          size="sm"
          :to="{name:'project.calendar',params:{projectId}}"
        >
          View calendar <span aria-hidden="true">→</span>
        </AppButton>
      </div>
      <div
        v-if="upcoming.isPending.value"
        class="mt-3 space-y-2"
      >
        <SkeletonBlock
          v-for="i in 2"
          :key="i"
          height="72px"
          rounded="0.75rem"
        />
      </div>
      <ErrorState
        v-else-if="upcoming.isError.value"
        class="mt-3"
        :error="upcoming.error.value"
        :retry="() => upcoming.refetch()"
      />
      <p
        v-else-if="!upcoming.events.value.length"
        class="mt-3 text-sm text-muted"
      >
        Nothing scheduled in the next two weeks. Add dates to Activities when you're ready.
      </p>
      <UpcomingList
        v-else
        :events="upcoming.events.value.slice(0, 5)"
        :timezone="project?.timezone ?? 'UTC'"
        compact
      />
      <p
        v-if="upcoming.events.value.length > 5"
        class="mt-2 text-meta text-muted"
      >
        Showing the next 5 events. View the calendar for the full schedule.
      </p>
    </section>

    <section
      v-if="!needsFirstCategory"
      aria-label="Project spending"
      class="border-t border-line pt-6"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <SectionHeading label="Budget" />
        <AppButton
          variant="ghost"
          size="sm"
          :to="{name:'project.budget',params:{projectId}}"
        >
          View Budget <span aria-hidden="true">→</span>
        </AppButton>
      </div>
      <SkeletonBlock
        v-if="financials.isPending.value"
        class="mt-3"
        height="104px"
        rounded="0.75rem"
      />
      <ErrorState
        v-else-if="financials.isError.value"
        class="mt-3"
        :error="financials.error.value"
        :retry="() => financials.refetch()"
      />
      <div
        v-else-if="financials.financials.value"
        class="mt-3 rounded-xl border border-line bg-surface p-5"
      >
        <dl class="grid gap-5 sm:grid-cols-3">
          <div>
            <dt class="text-meta text-muted">
              Budget
            </dt><dd class="mt-1 text-lg font-semibold tnum">
              {{ financials.financials.value.total_target_minor == null ? 'Not set' : format(financials.financials.value.total_target_minor, currency) }}
            </dd>
          </div>
          <div>
            <dt class="text-meta text-muted">
              Spent so far
            </dt><dd class="mt-1 text-lg font-semibold tnum">
              {{ format(financials.financials.value.net_actual_spend_minor, currency) }}
            </dd>
          </div>
          <div v-if="financials.financials.value.settled_variance_minor != null">
            <dt class="text-meta text-muted">
              {{ financials.financials.value.settled_variance_minor < 0 ? 'Over budget' : 'Remaining budget' }}
            </dt><dd
              class="mt-1 text-lg font-semibold tnum"
              :class="financials.financials.value.settled_variance_minor < 0 ? 'text-warning' : 'text-ink'"
            >
              {{ format(Math.abs(financials.financials.value.settled_variance_minor), currency) }}
            </dd>
          </div>
        </dl>
        <p class="mt-4 text-sm text-ink-soft">
          View Budget for member balances, settlement details and history.
        </p>
      </div>
      <p
        v-else
        class="mt-3 text-sm text-muted"
      >
        No budget summary available yet.
      </p>
    </section>

    <section
      aria-label="People"
      class="border-t border-line pt-6"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <SectionHeading label="People" />
        <AppButton
          variant="ghost"
          size="sm"
          :to="{name:'project.people',params:{projectId}}"
        >
          View People <span aria-hidden="true">→</span>
        </AppButton>
      </div>
      <SkeletonBlock
        v-if="directory.isPending.value"
        class="mt-3"
        height="44px"
      />
      <ErrorState
        v-else-if="directory.isError.value"
        class="mt-3"
        :error="directory.error.value"
        :retry="() => directory.refetch()"
      />
      <div
        v-else-if="roster.length"
        class="mt-3 flex flex-wrap items-center gap-3"
      >
        <div class="flex gap-1">
          <AppAvatar
            v-for="member in roster.slice(0, 4)"
            :key="member.member_id"
            :name="member.display_name"
            :url="member.avatar_url"
            :size="32"
          />
        </div>
        <p class="text-sm text-ink-soft">
          {{ roster.length }} {{ roster.length === 1 ? 'person' : 'people' }} involved<span v-if="invited"> · {{ invited }} invited</span>
        </p>
      </div>
      <p
        v-else
        class="mt-3 text-sm text-muted"
      >
        See who's involved and manage invitations in People.
      </p>
    </section>
  </div>
</template>

<script setup lang="ts">
import {computed, ref, watch} from 'vue';
import {useRoute} from 'vue-router';
import {useProjectContext} from '@/composables/useProjectContext';
import {useProjectHealth,useUpcoming,useProjectFinancials} from '@/composables/useProject';
import {useMoney} from '@/composables/useMoney';
import { paginateList } from '@/lib/pagination';
import SectionHeading from '@/components/ui/SectionHeading.vue';
import SkeletonBlock from '@/components/ui/SkeletonBlock.vue';
import ErrorState from '@/components/ui/ErrorState.vue';
import EmptyState from '@/components/ui/EmptyState.vue';
import AttentionRow from '@/components/health/AttentionRow.vue';
import UpcomingList from '@/components/timeline/UpcomingList.vue';
import MemberBalances from '@/components/budget/MemberBalances.vue';
const route=useRoute(),projectId=computed(()=>String(route.params.projectId));
const {project}=useProjectContext(),{format}=useMoney();
const financials=useProjectFinancials(projectId),health=useProjectHealth(projectId),upcoming=useUpcoming(projectId);
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
    <section aria-label="Project spending">
      <p v-if="financials.isPending.value">
        Loading spending…
      </p>
      <ErrorState
        v-else-if="financials.isError.value"
        :error="financials.error.value"
        :retry="()=>financials.refetch()"
      />
      <div
        v-else-if="financials.financials.value"
        class="grid gap-4 sm:grid-cols-2"
      >
        <div class="rounded-xl border border-line bg-surface p-5">
          <p class="text-13 text-muted">
            Budget
          </p><p class="mt-2 font-display text-2xl font-semibold">
            {{ financials.financials.value.total_target_minor==null?'Not set':format(financials.financials.value.total_target_minor,currency) }}
          </p>
        </div>
        <div class="rounded-xl border border-line bg-surface p-5">
          <p class="text-13 text-muted">
            Spent so far
          </p><p class="mt-2 font-display text-2xl font-semibold">
            {{ format(financials.financials.value.net_actual_spend_minor,currency) }}
          </p>
        </div>
      </div>
      <MemberBalances
        :project-id="projectId"
        :currency="currency"
      />
    </section>
    <div class="grid md:grid-cols-2 gap-8">
      <!-- Needs attention -->
      <div>
        <SectionHeading label="Needs attention" />
        <div
          v-if="health.isPending.value"
          class="mt-3 space-y-2"
        >
          <SkeletonBlock
            v-for="i in 3"
            :key="i"
            height="56px"
            rounded="0.5rem"
          />
        </div>
        <ErrorState
          v-else-if="health.isError.value"
          class="mt-3"
          :error="health.error.value"
          :retry="() => health.refetch()"
        />
        <EmptyState
          v-else-if="health.needsAttention.value.length === 0"
          class="mt-3"
          message="All clear — nothing needs attention on this project."
        />
        <div
          v-else
          class="mt-3"
        >
          <div class="border rounded-xl divide-y border-line bg-surface">
            <AttentionRow
              v-for="(f, i) in attentionPage.items"
              :key="f.code + (f.subject_id ?? '') + i"
              :finding="f"
            />
          </div>
          <div
            v-if="health.needsAttention.value.length > perPage"
            class="mt-3 flex items-center justify-between gap-3 text-13 text-muted"
          >
            <button
              type="button"
              class="rounded px-2 py-1 disabled:cursor-not-allowed disabled:opacity-40 hover:bg-[#F4F3F2]"
              :disabled="!attentionPage.canGoPrevious"
              aria-label="Previous needs attention page"
              @click="page = Math.max(1, page - 1)"
            >
              Previous
            </button>
            <span aria-live="polite">
              Page {{ attentionPage.page }} of {{ attentionPage.totalPages }}
            </span>
            <button
              type="button"
              class="rounded px-2 py-1 disabled:cursor-not-allowed disabled:opacity-40 hover:bg-[#F4F3F2]"
              :disabled="!attentionPage.canGoNext"
              aria-label="Next needs attention page"
              @click="page = Math.min(attentionPage.totalPages, page + 1)"
            >
              Next
            </button>
          </div>
        </div>
      </div>

      <!-- Upcoming -->
      <div>
        <SectionHeading label="Upcoming" />
        <div
          v-if="upcoming.isPending.value"
          class="mt-3 space-y-2"
        >
          <SkeletonBlock
            v-for="i in 2"
            :key="i"
            height="72px"
            rounded="0.5rem"
          />
        </div>
        <ErrorState
          v-else-if="upcoming.isError.value"
          class="mt-3"
          :error="upcoming.error.value"
          :retry="() => upcoming.refetch()"
        />
        <EmptyState
          v-else-if="upcoming.events.value.length === 0"
          class="mt-3"
          message="Nothing scheduled in the next two weeks."
        />
        <UpcomingList
          v-else
          :events="upcoming.events.value"
          :timezone="project?.timezone ?? 'UTC'"
        />
      </div>
    </div>
  </div>
</template>

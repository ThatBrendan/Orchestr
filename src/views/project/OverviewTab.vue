<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProjectHealth, useUpcoming } from "@/composables/useProject";
import SectionHeading from "@/components/ui/SectionHeading.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import AttentionRow from "@/components/health/AttentionRow.vue";
import UpcomingList from "@/components/timeline/UpcomingList.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project } = useProjectContext();

const health = useProjectHealth(projectId);
const upcoming = useUpcoming(projectId);
</script>

<template>
  <div class="grid md:grid-cols-2 gap-8 fade-in">
    <!-- Needs attention -->
    <div>
      <SectionHeading label="Needs attention" />
      <div v-if="health.isPending.value" class="mt-3 space-y-2">
        <SkeletonBlock v-for="i in 3" :key="i" height="56px" rounded="0.5rem" />
      </div>
      <ErrorState v-else-if="health.isError.value" class="mt-3" :error="health.error.value" :retry="() => health.refetch()" />
      <EmptyState
        v-else-if="health.needsAttention.value.length === 0"
        class="mt-3"
        message="All clear — nothing needs attention on this project."
      />
      <div v-else class="mt-3 border rounded-xl divide-y border-line bg-surface">
        <AttentionRow
          v-for="(f, i) in health.needsAttention.value"
          :key="f.code + (f.subject_id ?? '') + i"
          :finding="f"
        />
      </div>
    </div>

    <!-- Upcoming -->
    <div>
      <SectionHeading label="Upcoming" />
      <div v-if="upcoming.isPending.value" class="mt-3 space-y-2">
        <SkeletonBlock v-for="i in 2" :key="i" height="72px" rounded="0.5rem" />
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
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useFullTimeline } from "@/composables/useProject";
import { useProjectContext } from "@/composables/useProjectContext";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";

import TimelineStream from "@/components/timeline/TimelineStream.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project } = useProjectContext();
const timezone = computed(() => project.value?.timezone ?? "UTC");

const timeline = useFullTimeline(projectId);
</script>

<template>
  <div class="fade-in space-y-6 max-w-3xl">
    <div>
      <h2 class="text-section-heading">
        Timeline
      </h2>
      <p class="mt-1 mb-5 text-meta text-muted">
        Project dates in chronological order · {{ timezone }}
      </p>
      <div
        v-if="timeline.isPending.value"
        class="mt-3 space-y-2"
        role="status"
        aria-label="Loading timeline"
      >
        <SkeletonBlock
          v-for="i in 3"
          :key="i"
          height="72px"
          rounded="0.5rem"
        />
      </div>
      <ErrorState
        v-else-if="timeline.isError.value"
        class="mt-3"
        :error="timeline.error.value"
        :retry="() => timeline.refetch()"
      />
      <EmptyState
        v-else-if="timeline.events.value.length === 0"
        class="mt-3"
        message="Nothing on the timeline yet."
      />
      <TimelineStream
        v-else
        :events="timeline.events.value"
        :timezone="timezone"
      />
    </div>
  </div>
</template>

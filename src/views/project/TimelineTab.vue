<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useFullTimeline } from "@/composables/useProject";
import { useProjectContext } from "@/composables/useProjectContext";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import SectionHeading from "@/components/ui/SectionHeading.vue";
import UpcomingList from "@/components/timeline/UpcomingList.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project } = useProjectContext();
const timezone = computed(() => project.value?.timezone ?? "UTC");

const timeline = useFullTimeline(projectId);
</script>

<template>
  <div class="fade-in space-y-8">
    <div>
      <SectionHeading label="Full timeline" />
      <div
        v-if="timeline.isPending.value"
        class="mt-3 space-y-2"
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
      <UpcomingList
        v-else
        :events="timeline.events.value"
        :timezone="timezone"
      />
    </div>
  </div>
</template>

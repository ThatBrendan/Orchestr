<script setup lang="ts">
import PageContainer from "@/components/ui/PageContainer.vue";
import FeaturePending from "@/components/ui/FeaturePending.vue";
</script>

<template>
  <PageContainer width="md">
    <h1 class="font-display text-[26px] font-semibold tracking-tight">Calendar</h1>
    <p class="mt-1.5 text-14.5 text-ink-soft">A combined view of every deadline, booking and payment across your projects.</p>
    <div class="mt-8">
      <FeaturePending
        title="Cross-project calendar"
        detail="v_timeline_events already powers per-project 'Upcoming'. The unified calendar view is a later pass."
      />
    </div>
  </PageContainer>
</template>

<script setup lang="ts">
import PageContainer from "@/components/ui/PageContainer.vue";
import FeaturePending from "@/components/ui/FeaturePending.vue";
</script>

<template>
  <PageContainer width="md">
    <h1 class="font-display text-[26px] font-semibold tracking-tight">People</h1>
    <p class="mt-1.5 text-14.5 text-ink-soft">Everyone across every project, in one place.</p>
    <div class="mt-8">
      <FeaturePending
        title="Global people directory"
        detail="This is a cross-project 'contacts' concept (DOMAIN_MODEL §10, FUTURE). Per-project members are on each project's People tab."
      />
    </div>
  </PageContainer>
</template>

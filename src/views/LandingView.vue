<script setup lang="ts">
import MarketingHeader from "@/components/marketing/MarketingHeader.vue";
import MarketingFooter from "@/components/marketing/MarketingFooter.vue";
import HeroSection from "@/components/marketing/HeroSection.vue";
import PillarsSection from "@/components/marketing/PillarsSection.vue";
import HowItWorksSection from "@/components/marketing/HowItWorksSection.vue";
import UseCasesSection from "@/components/marketing/UseCasesSection.vue";
import FinalCtaSection from "@/components/marketing/FinalCtaSection.vue";
import { RouterLink } from "vue-router";


</script>

<template>
  <div class="min-h-screen bg-paper">
    <a
      href="#main"
      class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:px-3 focus:py-2 focus:rounded-lg focus:bg-ink focus:text-white text-13 font-medium"
    >
      Skip to content
    </a>

    <MarketingHeader />

    <main id="main">
      <HeroSection />
      <PillarsSection />
      <HowItWorksSection />
      <UseCasesSection />
      <section
        class="max-w-6xl mx-auto px-5 md:px-8 pb-14 grid md:grid-cols-2 gap-4"
        aria-label="Planning guides"
      >
        <RouterLink
          to="/group-trip-planning"
          class="rounded-2xl border border-line bg-surface p-6 hover:border-brand focus-ring"
        >
          <h2 class="text-lg font-bold">
            Group trip planning
          </h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-soft">
            Plan a trip with friends or family using shared activities, decisions and cost tracking.
          </p>
        </RouterLink>
        <RouterLink
          to="/group-event-planning"
          class="rounded-2xl border border-line bg-surface p-6 hover:border-brand focus-ring"
        >
          <h2 class="text-lg font-bold">
            Group event planning
          </h2>
          <p class="mt-2 text-sm leading-relaxed text-ink-soft">
            Coordinate a celebration with shared responsibilities, dates and costs.
          </p>
        </RouterLink>
      </section>
      <FinalCtaSection />
    </main>

    <MarketingFooter />
  </div>
</template>

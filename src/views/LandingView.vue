<script setup lang="ts">
import MarketingHeader from "@/components/marketing/MarketingHeader.vue";
import MarketingFooter from "@/components/marketing/MarketingFooter.vue";
import HeroSection from "@/components/marketing/HeroSection.vue";
import PillarsSection from "@/components/marketing/PillarsSection.vue";
import HowItWorksSection from "@/components/marketing/HowItWorksSection.vue";
import UseCasesSection from "@/components/marketing/UseCasesSection.vue";
import FinalCtaSection from "@/components/marketing/FinalCtaSection.vue";


</script>

<template>
  <div class="min-h-screen bg-paper overflow-x-hidden">
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
      <FinalCtaSection />
    </main>

    <MarketingFooter />
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useAuth } from "@/composables/useAuth";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import ProductPreview from "./ProductPreview.vue";
import { scrollToId } from "./scroll";

const { isAuthenticated } = useAuth();
const primary = computed(() =>
  isAuthenticated.value
    ? { to: { name: "dashboard" }, label: "Open Orchestrio" }
    : { to: { name: "signup" }, label: "Start planning" },
);
</script>

<template>
  <section class="relative overflow-hidden" aria-labelledby="hero-heading">
    <div class="max-w-6xl mx-auto px-5 md:px-8 pt-16 md:pt-24 pb-14 md:pb-20">
      <div class="max-w-2xl">
        <h1 id="hero-heading" class="font-display text-[34px] leading-[1.12] md:text-[52px] md:leading-[1.08] font-semibold tracking-tight">
          Turn complex plans into coordinated execution.
        </h1>
        <p class="mt-5 text-[16px] md:text-[18px] leading-relaxed text-ink-soft max-w-xl">
          Orchestrio brings costs, responsibilities, commitments, deadlines, logistics and progress into one shared
          workspace — so everyone sees what's happening, who owns it, what it costs, and what's at risk.
        </p>
        <div class="mt-8 flex flex-wrap items-center gap-3">
          <AppButton :to="primary.to" size="lg">
            {{ primary.label }}
            <AppIcon name="arrowRight" :size="16" />
          </AppButton>
          <AppButton href="#how-it-works" variant="secondary" size="lg" @click.prevent="scrollToId('how-it-works')">
            See how it works
          </AppButton>
        </div>
      </div>

      <div class="mt-12 md:mt-16">
        <ProductPreview class="max-w-3xl" />
      </div>
    </div>
  </section>
</template>

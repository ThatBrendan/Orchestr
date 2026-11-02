<script setup lang="ts">
import { computed } from "vue";
import { useAuth } from "@/composables/useAuth";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import ProductPreview from "./ProductPreview.vue";

const { isAuthenticated } = useAuth();
const primary = computed(() => isAuthenticated.value
  ? { to: { name: "dashboard" }, label: "Open Orchestrio" }
  : { to: { name: "signup" }, label: "Get started" });
</script>

<template>
  <section aria-labelledby="hero-heading">
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-14 md:py-20 lg:py-24 grid lg:grid-cols-[0.9fr_1.1fr] gap-12 lg:gap-10 items-center">
      <div>
        <p class="inline-flex rounded-full bg-brand-soft text-brand-dark px-3 py-2 text-13 font-semibold">
          Planning, beyond the group chat
        </p>
        <h1
          id="hero-heading"
          class="mt-6 text-[38px] sm:text-[48px] lg:text-[52px] leading-[1.12] font-bold tracking-tight"
        >
          Plans need more <span class="text-brand">than messages.</span>
        </h1>
        <p class="mt-5 text-base sm:text-lg leading-relaxed text-ink-soft max-w-xl">
          Turn scattered planning into organised execution. Bring Activities, people, decisions, dates and money into one calm, shared project.
        </p>
        <div class="mt-8 flex flex-wrap items-center gap-3">
          <AppButton
            :to="primary.to"
            size="lg"
          >
            {{ primary.label }} <AppIcon
              name="arrowRight"
              :size="16"
            />
          </AppButton>
          <AppButton
            :to="{ path: '/', hash: '#how-it-works' }"
            variant="secondary"
            size="lg"
          >
            See how it works
          </AppButton>
        </div>
        <p class="mt-6 flex items-start gap-2 text-13 leading-relaxed text-ink-soft">
          <AppIcon
            name="checkCircle"
            class="text-accent shrink-0 mt-0.5"
            :size="16"
          />
          Real-world coordination, without project-management complexity.
        </p>
      </div>
      <ProductPreview />
    </div>
  </section>
</template>

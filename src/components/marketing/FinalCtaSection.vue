<script setup lang="ts">
import { computed } from "vue";
import { useAuth } from "@/composables/useAuth";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
const { isAuthenticated } = useAuth();
const primary = computed(() => isAuthenticated.value
  ? { to: { name: "dashboard" }, label: "Open Orchestrio" }
  : { to: { name: "signup" }, label: "Get started" });
</script>

<template>
  <section
    class="max-w-6xl mx-auto px-5 md:px-8 pb-16 md:pb-24"
    aria-labelledby="cta-heading"
  >
    <div class="rounded-2xl bg-brand-dark px-6 py-14 sm:p-16 text-center text-white">
      <h2
        id="cta-heading"
        class="text-[28px] sm:text-4xl leading-tight font-bold"
      >
        Make the plan easier to run.
      </h2>
      <p class="mt-4 text-base leading-relaxed max-w-xl mx-auto">
        Bring the Activities, people, decisions, dates and money together. Keep the whole plan moving.
      </p>
      <AppButton
        :to="primary.to"
        variant="secondary"
        size="lg"
        class="mt-8"
      >
        {{ primary.label }} <AppIcon
          name="arrowRight"
          :size="16"
        />
      </AppButton>
      <p class="mt-5 text-sm">
        Start with a project. Invite the people involved.
      </p>
    </div>
  </section>
</template>

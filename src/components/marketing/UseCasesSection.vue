<script setup lang="ts">
import AppIcon from "@/components/ui/AppIcon.vue";
import type { IconName } from "@/components/ui/icons";
const cases: { title: string; body: string; icon: IconName; tone: string; cues: string[] }[] = [
  { title: "Group Trips & Holidays", body: "Bring everyone's plans, bookings and shared costs together before you go.", icon: "pin", tone: "bg-brand-soft text-brand", cues: ["Activities", "Decisions", "Shared costs", "Dates"] },
  { title: "Weddings & Milestones", body: "Keep the people and details behind a big day moving together.", icon: "diamond", tone: "bg-amber-soft text-amber", cues: ["People", "Deadlines", "Budget", "Decisions"] },
  { title: "House Moves & Projects", body: "Know who is handling each job, what it costs and when it needs to happen.", icon: "home", tone: "bg-accent-soft text-accent", cues: ["Activities", "Responsibilities", "Payments", "Timeline"] },
  { title: "Team Offsites & Launches", body: "From a team gathering to a product launch, turn shared goals into clear next steps.", icon: "flag", tone: "bg-brand-soft text-brand", cues: ["Ownership", "Decisions", "Deadlines", "Progress"] },
];
</script>

<template>
  <section
    id="use-cases"
    aria-labelledby="cases-heading"
  >
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24">
      <div class="text-center max-w-2xl mx-auto">
        <p class="text-13 font-semibold uppercase tracking-widest text-brand">
          Adaptable by design
        </p>
        <h2
          id="cases-heading"
          class="mt-3 text-[28px] sm:text-4xl leading-tight font-bold"
        >
          One way to organise very different plans.
        </h2>
        <p class="mt-4 text-base text-ink-soft">
          For your personal circle, your team and the plans that bring you together.
        </p>
      </div>
      <div class="mt-12 grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <article
          v-for="item in cases"
          :key="item.title"
          class="rounded-2xl border border-line bg-surface p-5 flex flex-col"
        >
          <div
            class="w-11 h-11 rounded-xl flex items-center justify-center"
            :class="item.tone"
          >
            <AppIcon
              :name="item.icon"
              :size="22"
            />
          </div>
          <h3 class="mt-5 text-base font-bold">
            {{ item.title }}
          </h3>
          <p class="mt-3 mb-5 text-sm leading-relaxed text-ink-soft">
            {{ item.body }}
          </p>
          <ul
            class="mt-auto flex flex-wrap gap-1.5"
            aria-label="Planning possibilities"
          >
            <li
              v-for="cue in item.cues"
              :key="cue"
              class="rounded-md border border-line bg-paper px-2 py-1 text-13 text-ink-soft"
            >
              {{ cue }}
            </li>
          </ul>
        </article>
      </div>
      <p class="mt-6 text-center text-sm text-muted">
        Different plans. The same need to keep people, decisions and progress connected.
      </p>
    </div>
  </section>
</template>

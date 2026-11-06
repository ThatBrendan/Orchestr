<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useAuth } from "@/composables/useAuth";
import AppButton from "@/components/ui/AppButton.vue";
import MarketingHeader from "@/components/marketing/MarketingHeader.vue";
import MarketingFooter from "@/components/marketing/MarketingFooter.vue";

const route = useRoute();
const trip = computed(() => route.path === "/group-trip-planning");
const { isAuthenticated } = useAuth();
const heading = computed(() => trip.value ? "Plan a group trip beyond the group chat." : "Organise an event together, beyond the group chat.");
const label = computed(() => trip.value ? "Group trip planning" : "Group event planning");
const counterpart = computed(() => trip.value
  ? { path: "/group-event-planning", text: "Planning a celebration with a group? Explore event planning with Orchestrio." }
  : { path: "/group-trip-planning", text: "Planning a trip with friends or family? Explore group trip planning with Orchestrio." });
const signup = computed(() => isAuthenticated.value ? "/app" : "/signup");

const faqs = computed(() => trip.value ? [
  { q: "How do you organise a group trip?", a: "Start a shared project, invite the people involved, then keep activities, decisions, dates, owners and shared costs together. Orchestrio helps the group coordinate the plan; bookings are made with the relevant travel providers." },
  { q: "How can friends plan a holiday together?", a: "Use a shared project to record activities and dates, gather votes on decisions, and give activities an owner so the next steps are clear." },
  { q: "How can everyone keep track of group trip costs?", a: "Record shared costs with cost splits and use reimbursements to see who owes whom. Any payment is completed outside Orchestrio." },
  { q: "How can a group keep everyone updated?", a: "Invite members into the project so they can refer to the shared activities, decisions, dates and notes. Keep using your usual chat for conversation." },
] : [
  { q: "How do you organise an event with a group?", a: "Create a shared project, invite participants and keep activities, decisions, owners, dates and shared costs connected in one place." },
  { q: "How can friends plan a party together?", a: "Use activities to record arrangements and next steps, then assign an owner and date so everyone can see who is handling what." },
  { q: "How do you divide event responsibilities?", a: "Give activities an owner and status. Members can see the responsibilities and progress in the shared project." },
  { q: "How can everyone keep track of event costs?", a: "Track shared costs with cost splits and reimbursements. Orchestrio records the coordination; payments take place outside the app." },
]);
</script>

<template>
  <div class="min-h-screen bg-paper">
    <a
      href="#main"
      class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:px-3 focus:py-2 focus:rounded-lg focus:bg-ink focus:text-white"
    >Skip to content</a>
    <MarketingHeader />
    <main id="main">
      <section class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24 grid lg:grid-cols-[1.1fr_0.9fr] gap-12 items-center">
        <div>
          <p class="inline-flex rounded-full bg-brand-soft text-brand-dark px-3 py-2 text-13 font-semibold">
            {{ label }} · Beyond the group chat
          </p>
          <h1 class="mt-6 text-[38px] sm:text-[48px] leading-[1.12] font-bold tracking-tight">
            {{ heading }}
          </h1>
          <p class="mt-5 text-base sm:text-lg leading-relaxed text-ink-soft max-w-xl">
            Bring the people, activities, decisions, dates and shared costs for your {{ trip ? 'trip' : 'event' }} into one collaborative planning workspace. Keep the conversation where it is; give the plan a place everyone can follow.
          </p>
          <AppButton
            :to="signup"
            size="lg"
            class="mt-8"
          >
            Get started
          </AppButton>
        </div>
        <div class="rounded-2xl border border-line bg-surface p-6 sm:p-8">
          <p class="text-13 font-semibold uppercase tracking-widest text-brand">
            A shared plan, at a glance
          </p>
          <ul class="mt-5 space-y-4 text-sm sm:text-base">
            <li
              v-for="feature in ['Activities with owners, dates and status', 'Decisions with options and group votes', 'Project dates, timeline and calendar', 'Shared costs, splits and reimbursements']"
              :key="feature"
              class="flex gap-3"
            >
              <span
                aria-hidden="true"
                class="text-accent"
              >✓</span><span>{{ feature }}</span>
            </li>
          </ul>
          <p class="mt-5 border-t border-line pt-4 text-13 text-muted">
            Orchestrio coordinates your plan. Make bookings and payments with the relevant providers.
          </p>
        </div>
      </section>
      <section class="border-y border-line bg-surface">
        <div class="max-w-4xl mx-auto px-5 md:px-8 py-14 md:py-18">
          <h2 class="text-2xl sm:text-3xl font-bold">
            {{ trip ? 'Group trip planning gets scattered fast.' : 'Event details spread across too many places.' }}
          </h2>
          <p class="mt-4 leading-relaxed text-ink-soft">
            Plans often start in a chat, then decisions land in a different thread, dates in a calendar, and costs in a spreadsheet or someone’s notes. Orchestrio gives your group one shared project to organise the details and see what needs attention.
          </p>
          <h2 class="mt-10 text-2xl sm:text-3xl font-bold">
            Coordinate the work as well as the ideas.
          </h2>
          <p class="mt-4 leading-relaxed text-ink-soft">
            Create activities for the arrangements, add an owner and date, and track progress. Use decisions to gather votes and record an outcome. Keep project notes and dates nearby, and use cost splits and reimbursements to clarify shared expenses.
          </p>
          <p class="mt-4 leading-relaxed text-ink-soft">
            That works for a weekend away, family holiday or birthday trip—or for a birthday celebration, family gathering, reunion or group weekend. Orchestrio helps organise the people and work around the occasion; it does not book travel or provide event suppliers.
          </p>
          <h2 class="mt-10 text-2xl sm:text-3xl font-bold">
            Keep the conversation. Give the plan a home.
          </h2>
          <p class="mt-4 leading-relaxed text-ink-soft">
            WhatsApp and other chats are useful for conversation and sharing. A shared planning workspace helps the group find the latest decision, responsibility, date and cost without expecting every important detail to stay visible in a message thread.
          </p>
          <RouterLink
            :to="counterpart.path"
            class="mt-6 inline-block font-semibold text-brand underline underline-offset-4"
          >
            {{ counterpart.text }}
          </RouterLink>
          <p class="mt-3">
            <RouterLink
              to="/"
              class="font-medium text-brand underline underline-offset-4"
            >
              See how Orchestrio helps groups plan together
            </RouterLink>
          </p>
        </div>
      </section>
      <section class="max-w-4xl mx-auto px-5 md:px-8 py-14 md:py-20">
        <h2 class="text-2xl sm:text-3xl font-bold">
          Frequently asked questions
        </h2>
        <div class="mt-6 divide-y divide-line border-y border-line">
          <article
            v-for="faq in faqs"
            :key="faq.q"
            class="py-5"
          >
            <h3 class="font-bold">
              {{ faq.q }}
            </h3>
            <p class="mt-2 text-sm sm:text-base leading-relaxed text-ink-soft">
              {{ faq.a }}
            </p>
          </article>
        </div>
      </section>
      <section class="max-w-6xl mx-auto px-5 md:px-8 pb-16 md:pb-24">
        <div class="rounded-2xl bg-brand-dark px-6 py-12 sm:p-14 text-center text-white">
          <h2 class="text-2xl sm:text-4xl font-bold">
            Make your next shared plan easier to run.
          </h2>
          <p class="mt-4 max-w-xl mx-auto">
            Start a project, invite your group and keep the details moving together.
          </p>
          <AppButton
            :to="signup"
            variant="secondary"
            size="lg"
            class="mt-7"
          >
            Get started
          </AppButton>
        </div>
      </section>
    </main>
    <MarketingFooter />
  </div>
</template>

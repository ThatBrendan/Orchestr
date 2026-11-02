<script setup lang="ts">
import AppIcon from "@/components/ui/AppIcon.vue";
</script>

<template>
  <section
    id="how-it-works"
    class="bg-surface border-b border-line"
    aria-labelledby="how-heading"
  >
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24">
      <div class="text-center max-w-2xl mx-auto">
        <p class="text-13 font-semibold uppercase tracking-widest text-brand">
          How it works
        </p>
        <h2
          id="how-heading"
          class="mt-3 text-[28px] sm:text-4xl leading-tight font-bold"
        >
          From scattered planning to clear execution.
        </h2>
        <p class="mt-4 text-base text-ink-soft">
          Activities, Decisions and shared money stay connected to the same plan.
        </p>
      </div>
      <div class="mt-12 grid lg:grid-cols-3 gap-5">
        <article class="rounded-2xl border border-line bg-paper p-5 sm:p-6 flex flex-col">
          <div class="w-11 h-11 rounded-xl bg-brand-soft text-brand flex items-center justify-center">
            <AppIcon
              name="checkCircle"
              :size="22"
            />
          </div>
          <h3 class="mt-5 text-lg font-bold">
            Know what needs to happen
          </h3>
          <p class="mt-2 mb-6 text-sm leading-relaxed text-ink-soft">
            Turn ideas into clear Activities. Give each one an owner, dates and a status so everyone knows the next step.
          </p>
          <div
            class="mt-auto rounded-xl border border-line bg-surface p-4 text-13 shadow-sm"
            aria-label="Example Activity"
          >
            <p class="text-muted mb-3">
              Activity · Launch preparation
            </p>
            <p class="font-semibold text-sm">
              Prepare the launch demo
            </p>
            <span class="inline-flex mt-2 rounded-full bg-brand-soft text-brand-dark px-2 py-1 font-medium">In progress</span>
            <div class="mt-4 pt-3 border-t border-line flex flex-wrap justify-between gap-2 text-ink-soft">
              <span class="inline-flex items-center gap-1.5"><AppIcon
                name="calendar"
                :size="14"
              />16 Jun · 10:00</span><span>Owner: Priya</span>
            </div>
          </div>
        </article>
        <article class="rounded-2xl border border-line bg-paper p-5 sm:p-6 flex flex-col">
          <div class="w-11 h-11 rounded-xl bg-accent-soft text-accent flex items-center justify-center">
            <AppIcon
              name="people"
              :size="22"
            />
          </div>
          <h3 class="mt-5 text-lg font-bold">
            Make decisions together
          </h3>
          <p class="mt-2 mb-6 text-sm leading-relaxed text-ink-soft">
            Create a Decision, gather votes and agree on an outcome. Turn the resolved result into an Activity to move it forward.
          </p>
          <div
            class="mt-auto rounded-xl border border-line bg-surface p-4 text-13 shadow-sm"
            aria-label="Example Decision"
          >
            <div class="flex flex-wrap justify-between gap-2 mb-3">
              <span class="text-muted">Decision</span><span class="text-accent font-medium">4 of 5 voted</span>
            </div>
            <p class="font-semibold text-sm">
              Choose the event format
            </p>
            <div class="mt-4 flex justify-between gap-2">
              <span>Demo &amp; discussion</span><strong class="text-accent">3 votes</strong>
            </div>
            <div
              class="mt-2 h-2 rounded-full bg-accent-soft"
              aria-hidden="true"
            >
              <div class="w-3/4 h-full rounded-full bg-accent" />
            </div>
            <div class="mt-3 flex justify-between gap-2 text-ink-soft">
              <span>Presentation</span><span>1 vote</span>
            </div>
          </div>
        </article>
        <article class="rounded-2xl border border-line bg-paper p-5 sm:p-6 flex flex-col">
          <div class="w-11 h-11 rounded-xl bg-amber-soft text-amber flex items-center justify-center">
            <AppIcon
              name="coins"
              :size="22"
            />
          </div>
          <h3 class="mt-5 text-lg font-bold">
            Keep money clear
          </h3>
          <p class="mt-2 mb-6 text-sm leading-relaxed text-ink-soft">
            Understand shared costs and who owes whom. Coordinate payments using members’ saved payment links.
          </p>
          <div
            class="mt-auto rounded-xl border border-line bg-surface p-4 text-13 shadow-sm"
            aria-label="Example reimbursement"
          >
            <p class="text-muted mb-3">
              Shared cost · Event materials
            </p>
            <div class="flex flex-wrap items-center justify-between gap-2">
              <p class="font-semibold text-sm">
                Alex owes Priya
              </p><strong class="text-xl text-accent">£32</strong>
            </div>
            <div class="mt-4 pt-3 border-t border-line flex items-start gap-2 text-ink-soft">
              <AppIcon
                name="banknote"
                :size="18"
                class="text-amber shrink-0"
              /><span>Priya’s saved payment link</span>
            </div>
            <p class="mt-3 text-13 text-muted">
              Payments happen outside Orchestrio.
            </p>
          </div>
        </article>
      </div>
    </div>
  </section>
</template>

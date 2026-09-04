<script setup lang="ts">
const SCATTERED = [
  "WhatsApp threads",
  "Email chains",
  "Spreadsheets",
  "PDFs",
  "Booking confirmations",
  "Scattered notes",
  "Payment reminders",
];

const MISSING =
  "what's happening, who owns it, what it costs, what's paid, what's outstanding, which deadlines are close, or what's at risk";
</script>

<template>
  <section class="bg-surface border-y border-line" aria-labelledby="problem-heading">
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-20">
      <h2 id="problem-heading" class="font-display text-[26px] md:text-[32px] font-semibold tracking-tight max-w-2xl">
        A complex plan doesn't fail all at once. It fragments.
      </h2>
      <p class="mt-4 text-[16px] leading-relaxed text-ink-soft max-w-2xl">
        The details end up spread across a dozen places, each owned by a different person, none of them complete.
      </p>

      <div class="mt-8 flex flex-wrap gap-2">
        <span
          v-for="s in SCATTERED"
          :key="s"
          class="px-3 py-1.5 rounded-full border border-line text-13.5 text-ink-soft bg-paper"
        >
          {{ s }}
        </span>
      </div>

      <div class="mt-10 border-l-2 border-amber pl-5 max-w-2xl">
        <p class="text-[16px] leading-relaxed text-ink">
          So nobody has one reliable view of <span class="text-ink-soft">{{ MISSING }}</span>.
        </p>
      </div>
    </div>
  </section>
</template>

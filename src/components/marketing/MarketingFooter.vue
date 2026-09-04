<script setup lang="ts">
import { RouterLink } from "vue-router";
import { APP_NAME } from "@/config";
import { scrollToId } from "./scroll";

const year = new Date().getFullYear();

// Section links scroll the landing page; auth links route. Legal/company pages
// don't exist yet — rendered as disabled placeholders, not fake links (spec §14).
const columns = [
  {
    heading: "Product",
    links: [
      { label: "Features", href: "#features" },
      { label: "Use cases", href: "#use-cases" },
      { label: "How it works", href: "#how-it-works" },
    ],
  },
];
</script>

<template>
  <footer class="border-t border-line bg-surface" aria-labelledby="footer-heading">
    <h2 id="footer-heading" class="sr-only">Site footer</h2>
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-14">
      <div class="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <div class="font-display font-semibold text-[17px] tracking-tight">{{ APP_NAME }}</div>
          <p class="mt-2 text-13 text-muted max-w-[16rem]">Plan together. Execute clearly.</p>
        </div>

        <nav v-for="col in columns" :key="col.heading" :aria-label="col.heading">
          <div class="text-13 font-semibold text-ink">{{ col.heading }}</div>
          <ul class="mt-3 space-y-2">
            <li v-for="l in col.links" :key="l.label">
              <a
                :href="l.href"
                class="text-13.5 text-ink-soft hover:text-ink focus-ring"
                @click.prevent="scrollToId(l.href)"
              >
                {{ l.label }}
              </a>
            </li>
          </ul>
        </nav>

        <nav aria-label="Company">
          <div class="text-13 font-semibold text-ink">Company</div>
          <ul class="mt-3 space-y-2">
            <li><span class="text-13.5 text-muted cursor-default" aria-disabled="true" title="Coming soon">About</span></li>
          </ul>
        </nav>

        <div class="flex flex-col gap-8">
          <nav aria-label="Legal">
            <div class="text-13 font-semibold text-ink">Legal</div>
            <ul class="mt-3 space-y-2">
              <li>
                <span class="text-13.5 text-muted cursor-default" aria-disabled="true" title="Coming soon">Privacy</span>
              </li>
              <li>
                <span class="text-13.5 text-muted cursor-default" aria-disabled="true" title="Coming soon">Terms</span>
              </li>
            </ul>
          </nav>
          <nav aria-label="Account">
            <div class="text-13 font-semibold text-ink">Account</div>
            <ul class="mt-3 space-y-2">
              <li>
                <RouterLink :to="{ name: 'login' }" class="text-13.5 text-ink-soft hover:text-ink focus-ring"
                  >Log in</RouterLink
                >
              </li>
              <li>
                <RouterLink :to="{ name: 'signup' }" class="text-13.5 text-ink-soft hover:text-ink focus-ring"
                  >Sign up</RouterLink
                >
              </li>
            </ul>
          </nav>
        </div>
      </div>

      <div class="mt-12 pt-6 border-t border-line flex flex-wrap items-center justify-between gap-3">
        <p class="text-13 text-muted">© {{ year }} {{ APP_NAME }}. All rights reserved.</p>
        <p class="text-13 text-muted">Privacy and Terms pages are in progress.</p>
      </div>
    </div>
  </footer>
</template>

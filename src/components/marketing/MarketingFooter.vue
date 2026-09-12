<script setup lang="ts">
import { RouterLink } from "vue-router";
import { APP_NAME, PUBLIC_CONTACT_EMAIL } from "@/config";
import orchestrioIcon from "@/assets/orchestrio-icon.svg";
import { PUBLIC_SECTION_LINKS } from "./scroll";

const year = new Date().getFullYear();

// Section links scroll the landing page; public pages and auth links use the router.
const columns = [
  {
    heading: "Product",
    links: [
      ...PUBLIC_SECTION_LINKS.slice().reverse(),
    ],
  },
];
</script>

<template>
  <footer
    class="border-t border-line bg-surface"
    aria-labelledby="footer-heading"
  >
    <h2
      id="footer-heading"
      class="sr-only"
    >
      Site footer
    </h2>
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-14">
      <div class="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <RouterLink
            to="/"
            :aria-label="`${APP_NAME} home`"
            class="inline-flex focus-ring"
          >
            <img
              :src="orchestrioIcon"
              alt=""
              class="h-12 w-auto"
            >
          </RouterLink>
          <p class="mt-2 text-13 text-muted max-w-[16rem]">
            Plan together. Execute clearly.
          </p>
        </div>

        <nav
          v-for="col in columns"
          :key="col.heading"
          :aria-label="col.heading"
        >
          <div class="text-13 font-semibold text-ink">
            {{ col.heading }}
          </div>
          <ul class="mt-3 space-y-2">
            <li
              v-for="l in col.links"
              :key="l.label"
            >
              <RouterLink
                :to="l.to"
                class="text-13.5 text-ink-soft hover:text-ink focus-ring"
              >
                {{ l.label }}
              </RouterLink>
            </li>
          </ul>
        </nav>

        <nav aria-label="Company">
          <div class="text-13 font-semibold text-ink">
            Company
          </div>
          <ul class="mt-3 space-y-2">
            <li>
              <RouterLink
                :to="{ name: 'about' }"
                class="text-13.5 text-ink-soft hover:text-ink focus-ring"
              >
                About
              </RouterLink>
            </li>
            <li>
              <a
                :href="`mailto:${PUBLIC_CONTACT_EMAIL}`"
                class="text-13.5 text-ink-soft hover:text-ink focus-ring [overflow-wrap:anywhere]"
              >{{ PUBLIC_CONTACT_EMAIL }}</a>
            </li>
          </ul>
        </nav>

        <div class="flex flex-col gap-8">
          <nav aria-label="Legal">
            <div class="text-13 font-semibold text-ink">
              Legal
            </div>
            <ul class="mt-3 space-y-2">
              <li>
                <RouterLink
                  :to="{ name: 'privacy' }"
                  class="text-13.5 text-ink-soft hover:text-ink focus-ring"
                >
                  Privacy
                </RouterLink>
              </li>
              <li>
                <RouterLink
                  :to="{ name: 'terms' }"
                  class="text-13.5 text-ink-soft hover:text-ink focus-ring"
                >
                  Terms
                </RouterLink>
              </li>
            </ul>
          </nav>
          <nav aria-label="Account">
            <div class="text-13 font-semibold text-ink">
              Account
            </div>
            <ul class="mt-3 space-y-2">
              <li>
                <RouterLink
                  :to="{ name: 'login' }"
                  class="text-13.5 text-ink-soft hover:text-ink focus-ring"
                >
                  Log in
                </RouterLink>
              </li>
              <li>
                <RouterLink
                  :to="{ name: 'signup' }"
                  class="text-13.5 text-ink-soft hover:text-ink focus-ring"
                >
                  Sign up
                </RouterLink>
              </li>
            </ul>
          </nav>
        </div>
      </div>

      <div class="mt-12 pt-6 border-t border-line flex flex-wrap items-center justify-between gap-3">
        <p class="text-13 text-muted">
          © {{ year }} {{ APP_NAME }}. All rights reserved.
        </p>
        <p class="text-13 text-muted">
          Plan together. Execute clearly.
        </p>
      </div>
    </div>
  </footer>
</template>

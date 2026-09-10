<script setup lang="ts">
import { ref, onMounted, onUnmounted } from "vue";
import { RouterLink } from "vue-router";
import { Disclosure, DisclosureButton, DisclosurePanel } from "@headlessui/vue";
import { useAuth } from "@/composables/useAuth";
import { APP_NAME } from "@/config";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import orchestrioIcon from "@/assets/orchestrio-icon.svg";
import { MARKETING_NAV, scrollToId } from "./scroll";

const { isAuthenticated } = useAuth();

const scrolled = ref(false);
function onScroll() {
  scrolled.value = window.scrollY > 8;
}
onMounted(() => {
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
});
onUnmounted(() => window.removeEventListener("scroll", onScroll));

function go(href: string, close?: () => void) {
  scrollToId(href);
  close?.();
}
</script>

<template>
  <Disclosure v-slot="{ open, close }" as="header" class="sticky top-0 z-30">
    <div
      class="border-b transition-colors"
      :class="scrolled || open ? 'bg-surface/95 backdrop-blur border-line' : 'border-transparent'"
    >
      <div class="max-w-6xl mx-auto px-5 md:px-8">
        <div class="h-16 flex items-center justify-between gap-4">
          <RouterLink :to="{ name: 'landing' }" class="flex items-center focus-ring" :aria-label="APP_NAME">
            <img :src="orchestrioIcon" :alt="APP_NAME" class="h-12 w-auto" />
          </RouterLink>

          <nav class="hidden md:flex items-center gap-1" aria-label="Marketing">
            <a
              v-for="item in MARKETING_NAV"
              :key="item.href"
              :href="item.href"
              class="px-3 py-2 rounded-lg text-14 font-medium text-ink-soft hover:text-ink hover:bg-[#F0F0EE] transition-colors focus-ring"
              @click.prevent="go(item.href)"
            >
              {{ item.label }}
            </a>
          </nav>

          <div class="hidden md:flex items-center gap-2">
            <AppButton v-if="isAuthenticated" :to="{ name: 'dashboard' }" size="sm">Open {{ APP_NAME }}</AppButton>
            <template v-else>
              <AppButton :to="{ name: 'login' }" variant="ghost" size="sm">Log in</AppButton>
              <AppButton :to="{ name: 'signup' }" size="sm">Get started</AppButton>
            </template>
          </div>

          <DisclosureButton
            class="md:hidden w-9 h-9 -mr-1 rounded-lg flex items-center justify-center text-ink-soft hover:bg-[#F0F0EE] focus-ring"
            :aria-label="open ? 'Close menu' : 'Open menu'"
          >
            <AppIcon :name="open ? 'close' : 'menu'" :size="18" />
          </DisclosureButton>
        </div>
      </div>
    </div>

    <DisclosurePanel class="md:hidden border-b border-line bg-surface shadow-sm">
      <nav class="max-w-6xl mx-auto px-5 py-3 flex flex-col" aria-label="Marketing">
        <a
          v-for="item in MARKETING_NAV"
          :key="item.href"
          :href="item.href"
          class="px-2 py-2.5 rounded-lg text-14.5 font-medium text-ink-soft hover:bg-[#F0F0EE] focus-ring"
          @click.prevent="go(item.href, close)"
        >
          {{ item.label }}
        </a>
        <div class="mt-2 pt-3 border-t border-line flex flex-col gap-2">
          <AppButton v-if="isAuthenticated" :to="{ name: 'dashboard' }" block>Open {{ APP_NAME }}</AppButton>
          <template v-else>
            <AppButton :to="{ name: 'login' }" variant="secondary" block>Log in</AppButton>
            <AppButton :to="{ name: 'signup' }" block>Get started</AppButton>
          </template>
        </div>
      </nav>
    </DisclosurePanel>
  </Disclosure>
</template>

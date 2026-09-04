<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { NAV_ITEMS } from "./navItems";
import { APP_NAME } from "@/config";
import AppIcon from "@/components/ui/AppIcon.vue";
import CurrentProjectLink from "./CurrentProjectLink.vue";
import UserMenu from "./UserMenu.vue";

const route = useRoute();
const activeName = computed(() => String(route.name ?? ""));
function isActive(match: string[]) {
  return match.some((m) => activeName.value === m || activeName.value.startsWith(m));
}
</script>

<template>
  <aside class="hidden md:flex w-60 shrink-0 border-r border-line bg-surface flex-col">
    <div class="h-16 flex items-center px-5 border-b border-line">
      <span class="font-display font-semibold text-[17px] tracking-tight">{{ APP_NAME }}</span>
    </div>

    <nav class="flex-1 px-3 py-4 space-y-0.5">
      <RouterLink
        v-for="item in NAV_ITEMS"
        :key="item.label"
        :to="item.to"
        class="nav-item flex items-center gap-3 px-3 py-2 rounded-lg text-14 font-medium focus-ring transition-colors"
        :class="isActive(item.match) ? 'text-ink bg-[#F0F0EE]' : 'text-ink-soft hover:bg-[#F6F6F4]'"
      >
        <AppIcon :name="item.icon" :size="18" />
        <span>{{ item.label }}</span>
      </RouterLink>
    </nav>

    <CurrentProjectLink />

    <UserMenu />
  </aside>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { NAV_ITEMS } from "./navItems";
import orchestrioIcon from "@/assets/orchestrio-icon.svg";
import { useMyProfile } from "@/composables/useDashboard";
import AppIcon from "@/components/ui/AppIcon.vue";
import CurrentProjectLink from "./CurrentProjectLink.vue";
import UserMenu from "./UserMenu.vue";

const route = useRoute();
const { profile } = useMyProfile();
const items = computed(() =>
  profile.value?.platform_role === "admin"
    ? [...NAV_ITEMS, { to: { name: "admin.dashboard" }, label: "Admin", shortLabel: "Admin", icon: "flag", match: ["admin."] } as const]
    : NAV_ITEMS,
);
const activeName = computed(() => String(route.name ?? ""));
function isActive(match: readonly string[]) {
  return match.some((m) => activeName.value === m || activeName.value.startsWith(m));
}
</script>

<template>
  <aside class="hidden md:flex w-60 shrink-0 border-r border-line bg-surface flex-col">
    <RouterLink to="/" class="h-16 flex items-center px-5 border-b border-line focus-ring">
      <img :src="orchestrioIcon" alt="Orchestrio" class="h-12 w-auto" />
    </RouterLink>

    <nav class="flex-1 px-3 py-4 space-y-0.5">
      <RouterLink
        v-for="item in items"
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

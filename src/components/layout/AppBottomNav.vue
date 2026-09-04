<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { NAV_ITEMS } from "./navItems";
import AppIcon from "@/components/ui/AppIcon.vue";

const route = useRoute();
const activeName = computed(() => String(route.name ?? ""));
function isActive(match: string[]) {
  return match.some((m) => activeName.value === m || activeName.value.startsWith(m));
}
</script>

<template>
  <nav
    class="md:hidden fixed bottom-0 left-0 right-0 h-16 border-t border-line bg-surface flex items-stretch z-10"
  >
    <RouterLink
      v-for="item in NAV_ITEMS"
      :key="item.label"
      :to="item.to"
      class="flex-1 flex flex-col items-center justify-center gap-1"
      :class="isActive(item.match) ? 'text-ink' : 'text-muted'"
    >
      <AppIcon :name="item.icon" :size="18" />
      <span class="text-[11px]">{{ item.shortLabel }}</span>
    </RouterLink>
  </nav>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { RouterView, useRoute } from "vue-router";
import { APP_NAME } from "@/config";
import orchestrioIcon from "@/assets/orchestrio-icon.svg";
import AppIcon from "@/components/ui/AppIcon.vue";
import UserMenu from "@/components/layout/UserMenu.vue";

const route = useRoute();

const items = [
  { to: { name: "admin.dashboard" }, label: "Overview", icon: "home", match: ["admin.dashboard"] },
  { to: { name: "admin.users" }, label: "Users", icon: "people", match: ["admin.users", "admin.user"] },
  { to: { name: "admin.projects" }, label: "Projects", icon: "projects", match: ["admin.projects", "admin.project"] },
  { to: { name: "admin.invitations" }, label: "Invitations", icon: "calendar", match: ["admin.invitations"] },
  { to: { name: "admin.audit" }, label: "Audit", icon: "flag", match: ["admin.audit"] },
] as const;

const activeName = computed(() => String(route.name ?? ""));
function isActive(match: readonly string[]) {
  return match.some((m) => activeName.value === m || activeName.value.startsWith(m));
}
</script>

<template>
  <div class="min-h-screen bg-canvas md:flex">
    <aside class="hidden md:flex w-64 shrink-0 border-r border-line bg-surface flex-col">
      <RouterLink
        to="/"
        class="h-16 flex items-center px-5 border-b border-line focus-ring"
      >
        <img
          :src="orchestrioIcon"
          :alt="APP_NAME"
          class="h-12 w-auto"
        >
        <span class="ml-2 rounded bg-ink px-1.5 py-0.5 text-[11px] font-semibold uppercase text-white">Admin</span>
      </RouterLink>

      <nav class="flex-1 px-3 py-4 space-y-0.5">
        <RouterLink
          v-for="item in items"
          :key="item.label"
          :to="item.to"
          class="nav-item flex items-center gap-3 px-3 py-2 rounded-lg text-14 font-medium focus-ring transition-colors"
          :class="isActive(item.match) ? 'text-brand-dark bg-brand-soft' : 'text-ink-soft hover:bg-secondary'"
        >
          <AppIcon
            :name="item.icon"
            :size="18"
          />
          <span>{{ item.label }}</span>
        </RouterLink>
      </nav>

      <div class="px-3 py-3 border-t border-line">
        <RouterLink
          :to="{ name: 'dashboard' }"
          class="flex items-center gap-2 rounded-lg px-3 py-2 text-14 font-medium text-ink-soft hover:bg-[#F6F6F4] focus-ring"
        >
          <AppIcon
            name="arrowRight"
            :size="16"
          />
          <span>Open Orchestrio</span>
        </RouterLink>
      </div>
      <UserMenu />
    </aside>

    <div class="min-w-0 flex-1">
      <header class="md:hidden sticky top-0 z-10 border-b border-line bg-surface">
        <div class="min-h-14 flex flex-wrap items-center justify-between gap-2 px-4">
          <RouterLink
            to="/"
            aria-label="Orchestrio home"
            class="flex min-h-11 items-center gap-2 focus-ring"
          >
            <img
              :src="orchestrioIcon"
              :alt="APP_NAME"
              class="h-7 w-auto"
            >
            <span class="rounded bg-ink px-1.5 py-0.5 text-[10px] font-semibold uppercase text-white">Admin</span>
          </RouterLink>
          <RouterLink
            :to="{ name: 'dashboard' }"
            class="text-13 font-medium text-ink-soft focus-ring"
          >
            Open Orchestrio
          </RouterLink>
          <UserMenu compact />
        </div>
        <nav class="flex overflow-x-auto px-2 pb-2">
          <RouterLink
            v-for="item in items"
            :key="item.label"
            :to="item.to"
            class="shrink-0 rounded-lg px-3 py-1.5 text-13 font-medium focus-ring"
            :class="isActive(item.match) ? 'bg-brand-soft text-brand-dark' : 'text-muted'"
          >
            {{ item.label }}
          </RouterLink>
        </nav>
      </header>

      <main class="min-w-0 pb-10">
        <RouterView />
      </main>
    </div>
  </div>
</template>

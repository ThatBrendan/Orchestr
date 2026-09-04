<script setup lang="ts">
import { useRouter } from "vue-router";
import { Menu, MenuButton, MenuItems, MenuItem } from "@headlessui/vue";
import { useAuth } from "@/composables/useAuth";
import { useMyProfile } from "@/composables/useDashboard";
import AppAvatar from "@/components/ui/AppAvatar.vue";

const { email, signOut } = useAuth();
const { profile } = useMyProfile();
const router = useRouter();

async function handleSignOut() {
  await signOut();
  await router.push({ name: "login" });
}
</script>

<template>
  <Menu as="div" class="relative px-3 py-3 border-t border-line">
    <MenuButton class="w-full flex items-center gap-2.5 px-2 py-1.5 rounded-lg hover:bg-[#F6F6F4] focus-ring">
      <AppAvatar :name="profile?.display_name ?? email ?? '?'" :url="profile?.avatar_url" :size="28" tone="ink" />
      <span class="text-[13.5px] font-medium truncate">{{ profile?.display_name ?? email }}</span>
    </MenuButton>
    <MenuItems
      class="absolute bottom-full left-3 right-3 mb-1 rounded-lg border border-line bg-surface shadow-sm py-1 focus:outline-none"
    >
      <MenuItem v-slot="{ active }">
        <RouterLink
          :to="{ name: 'settings' }"
          class="block px-3 py-2 text-14"
          :class="active ? 'bg-[#F6F6F4]' : ''"
        >
          Settings
        </RouterLink>
      </MenuItem>
      <MenuItem v-slot="{ active }">
        <button
          class="w-full text-left px-3 py-2 text-14 text-danger"
          :class="active ? 'bg-[#F6F6F4]' : ''"
          @click="handleSignOut"
        >
          Sign out
        </button>
      </MenuItem>
    </MenuItems>
  </Menu>
</template>

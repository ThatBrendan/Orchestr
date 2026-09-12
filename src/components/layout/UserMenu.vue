<script setup lang="ts">
import { Menu, MenuButton, MenuItems, MenuItem } from "@headlessui/vue";
import { useAuth } from "@/composables/useAuth";
import { useMyProfile } from "@/composables/useDashboard";
import AppAvatar from "@/components/ui/AppAvatar.vue";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";

withDefaults(defineProps<{ compact?: boolean }>(), { compact: false });
const { email, signOut, signingOut } = useAuth();
const { profile } = useMyProfile();
const toast = useToast();

async function handleSignOut(close: () => void) {
  close();
  try {
    await signOut();
  } catch (error) {
    toast.error(toAppError(error).message);
  }
}
</script>

<template>
  <Menu
    v-slot="{ close }"
    as="div"
    class="relative"
    :class="compact ? 'shrink-0' : 'px-3 py-3 border-t border-line'"
  >
    <MenuButton
      aria-label="Account menu"
      class="min-h-11 min-w-11 flex items-center justify-center gap-2.5 px-2 py-1.5 rounded-lg hover:bg-[#F6F6F4] focus-ring"
      :class="compact ? '' : 'w-full'"
    >
      <AppAvatar
        :name="profile?.display_name ?? email ?? '?'"
        :url="profile?.avatar_url"
        :size="28"
        tone="ink"
      />
      <span
        v-if="!compact"
        class="text-[13.5px] font-medium truncate"
      >{{ profile?.display_name ?? email }}</span>
    </MenuButton>
    <MenuItems
      class="absolute z-20 rounded-lg border border-line bg-surface shadow-sm py-1 focus:outline-none"
      :class="compact ? 'top-full right-0 mt-1 w-48 max-w-[calc(100vw-2rem)]' : 'bottom-full left-3 right-3 mb-1'"
    >
      <MenuItem v-slot="{ active }">
        <RouterLink
          :to="{ name: 'settings' }"
          class="flex min-h-11 items-center px-3 py-2 text-14"
          :class="active ? 'bg-[#F6F6F4]' : ''"
        >
          Settings
        </RouterLink>
      </MenuItem>
      <MenuItem
        v-slot="{ active }"
        :disabled="signingOut"
      >
        <button
          type="button"
          :disabled="signingOut"
          class="min-h-11 w-full text-left px-3 py-2 text-14 text-danger disabled:opacity-50"
          :class="active ? 'bg-[#F6F6F4]' : ''"
          @click="handleSignOut(close)"
        >
          Sign out
        </button>
      </MenuItem>
    </MenuItems>
  </Menu>
</template>

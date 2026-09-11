<script setup lang="ts">
import { ref } from "vue";
import { useAdminUsers } from "@/composables/useAdmin";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";

const search = ref("");
const { users, isPending, isError, error, refetch } = useAdminUsers(search);

function date(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value));
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-6 md:px-8 md:py-8">
    <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">
          Users
        </h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">
          Search and inspect platform accounts.
        </p>
      </div>
      <input
        v-model="search"
        type="search"
        class="h-10 w-full rounded-lg border border-line bg-surface px-3 text-14 focus-ring sm:w-72"
        placeholder="Search users"
      >
    </div>

    <div class="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
      <SkeletonBlock
        v-if="isPending"
        height="360px"
        rounded="0"
      />
      <ErrorState
        v-else-if="isError"
        :error="error"
        :retry="() => refetch()"
      />
      <EmptyState
        v-else-if="users.length === 0"
        message="No users found."
      />
      <table
        v-else
        class="w-full min-w-[760px] text-left text-14"
      >
        <thead class="border-b border-line text-12 uppercase text-muted">
          <tr>
            <th class="px-4 py-3 font-medium">
              User
            </th>
            <th class="px-4 py-3 font-medium">
              Email
            </th>
            <th class="px-4 py-3 font-medium">
              Role
            </th>
            <th class="px-4 py-3 font-medium">
              Projects
            </th>
            <th class="px-4 py-3 font-medium">
              Joined
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          <tr
            v-for="user in users"
            :key="user.id"
            class="hover:bg-[#FBFBFA]"
          >
            <td class="px-4 py-3">
              <RouterLink
                :to="{ name: 'admin.user', params: { userId: user.id } }"
                class="font-medium text-ink focus-ring"
              >
                {{ user.display_name }}
              </RouterLink>
            </td>
            <td class="px-4 py-3 text-ink-soft">
              {{ user.email }}
            </td>
            <td class="px-4 py-3">
              <StatusBadge
                :label="user.platform_role"
                :tone="user.platform_role === 'admin' ? 'accent' : 'neutral'"
              />
            </td>
            <td class="px-4 py-3 text-ink-soft">
              {{ user.active_membership_count }} active / {{ user.membership_count }} total
            </td>
            <td class="px-4 py-3 text-muted">
              {{ date(user.created_at) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

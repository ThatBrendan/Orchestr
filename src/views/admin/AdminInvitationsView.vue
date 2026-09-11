<script setup lang="ts">
import { ref } from "vue";
import { useAdminInvitations } from "@/composables/useAdmin";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import { presentLabel } from "@/lib/presentation";

const search = ref("");
const { invitations, isPending, isError, error, refetch } = useAdminInvitations(search);

function date(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value)) : "-";
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-6 md:px-8 md:py-8">
    <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">
          Invitations
        </h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">
          Read-only platform invitation inspection.
        </p>
      </div>
      <input
        v-model="search"
        type="search"
        class="h-10 w-full rounded-lg border border-line bg-surface px-3 text-14 focus-ring sm:w-72"
        placeholder="Search invitations"
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
        v-else-if="invitations.length === 0"
        message="No invitations found."
      />
      <table
        v-else
        class="w-full min-w-[880px] text-left text-14"
      >
        <thead class="border-b border-line text-12 uppercase text-muted">
          <tr>
            <th class="px-4 py-3 font-medium">
              Invitee
            </th>
            <th class="px-4 py-3 font-medium">
              Project
            </th>
            <th class="px-4 py-3 font-medium">
              Role
            </th>
            <th class="px-4 py-3 font-medium">
              Status
            </th>
            <th class="px-4 py-3 font-medium">
              Inviter
            </th>
            <th class="px-4 py-3 font-medium">
              Created
            </th>
            <th class="px-4 py-3 font-medium">
              Expires
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          <tr
            v-for="invite in invitations"
            :key="invite.id"
          >
            <td class="px-4 py-3 font-medium text-ink">
              {{ invite.email }}
            </td>
            <td class="px-4 py-3">
              <RouterLink
                :to="{ name: 'admin.project', params: { projectId: invite.project_id } }"
                class="text-ink-soft focus-ring"
              >
                {{ invite.project_name }}
              </RouterLink>
            </td>
            <td class="px-4 py-3 text-ink-soft">
              {{ presentLabel(invite.role) }}
            </td>
            <td class="px-4 py-3">
              <StatusBadge :label="presentLabel(invite.status)" />
            </td>
            <td class="px-4 py-3 text-ink-soft">
              {{ invite.inviter_display_name ?? invite.inviter_email ?? "-" }}
            </td>
            <td class="px-4 py-3 text-muted">
              {{ date(invite.created_at) }}
            </td>
            <td class="px-4 py-3 text-muted">
              {{ date(invite.expires_at) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

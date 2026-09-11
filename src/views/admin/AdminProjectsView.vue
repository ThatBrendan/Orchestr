<script setup lang="ts">
import { ref } from "vue";
import { useAdminProjects } from "@/composables/useAdmin";
import { useMoney } from "@/composables/useMoney";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import { presentLabel } from "@/lib/presentation";

const search = ref("");
const { projects, isPending, isError, error, refetch } = useAdminProjects(search);
const { format } = useMoney();

function date(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value)) : "-";
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-6 md:px-8 md:py-8">
    <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">
          Projects
        </h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">
          Inspect platform projects without mutation controls.
        </p>
      </div>
      <input
        v-model="search"
        type="search"
        class="h-10 w-full rounded-lg border border-line bg-surface px-3 text-14 focus-ring sm:w-72"
        placeholder="Search projects"
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
        v-else-if="projects.length === 0"
        message="No projects found."
      />
      <table
        v-else
        class="w-full min-w-[900px] text-left text-14"
      >
        <thead class="border-b border-line text-12 uppercase text-muted">
          <tr>
            <th class="px-4 py-3 font-medium">
              Project
            </th>
            <th class="px-4 py-3 font-medium">
              Status
            </th>
            <th class="px-4 py-3 font-medium">
              Members
            </th>
            <th class="px-4 py-3 font-medium">
              Creator
            </th>
            <th class="px-4 py-3 font-medium">
              Spend
            </th>
            <th class="px-4 py-3 font-medium">
              Updated
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          <tr
            v-for="project in projects"
            :key="project.id"
            class="hover:bg-[#FBFBFA]"
          >
            <td class="px-4 py-3">
              <RouterLink
                :to="{ name: 'admin.project', params: { projectId: project.id } }"
                class="font-medium text-ink focus-ring"
              >
                {{ project.name }}
              </RouterLink>
              <div class="text-12 text-muted">
                {{ project.id }}
              </div>
            </td>
            <td class="px-4 py-3">
              <StatusBadge :label="presentLabel(project.deleted_at ? 'deleted' : project.status)" />
            </td>
            <td class="px-4 py-3 text-ink-soft">
              {{ project.active_member_count }} active / {{ project.member_count }} total
            </td>
            <td class="px-4 py-3 text-ink-soft">
              {{ project.created_by_display_name ?? project.created_by_email ?? "-" }}
            </td>
            <td class="px-4 py-3 text-ink-soft">
              {{ format(project.total_cost_minor, project.currency) }}
            </td>
            <td class="px-4 py-3 text-muted">
              {{ date(project.updated_at) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

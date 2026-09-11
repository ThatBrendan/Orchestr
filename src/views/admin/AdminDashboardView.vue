<script setup lang="ts">
import { computed } from "vue";
import { useAdminAudit, useAdminOverview, useAdminProjects, useAdminUsers } from "@/composables/useAdmin";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import StatTile from "@/components/ui/StatTile.vue";
import { presentAuditAction, presentLabel } from "@/lib/presentation";

const emptySearch = computed(() => "");
const { overview, isPending, isError, error, refetch } = useAdminOverview();
const users = useAdminUsers(emptySearch);
const projects = useAdminProjects(emptySearch);
const audit = useAdminAudit(emptySearch);

const recentUsers = computed(() => users.users.value.slice(0, 5));
const recentProjects = computed(() => projects.projects.value.slice(0, 5));
const recentAudit = computed(() => audit.events.value.slice(0, 6));

function date(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value)) : "-";
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-6 md:px-8 md:py-8">
    <div>
      <h1 class="font-display text-[26px] font-semibold tracking-tight">
        Admin Overview
      </h1>
      <p class="mt-1.5 text-14.5 text-ink-soft">
        Platform-wide operational snapshot.
      </p>
    </div>

    <div class="mt-7">
      <template v-if="isPending">
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <SkeletonBlock
            v-for="i in 8"
            :key="i"
            height="76px"
            rounded="0.5rem"
          />
        </div>
      </template>
      <ErrorState
        v-else-if="isError"
        :error="error"
        :retry="() => refetch()"
      />
      <div
        v-else-if="overview"
        class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4"
      >
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.total_users)"
            label="Total users"
          />
        </div>
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.admin_users)"
            label="Platform admins"
          />
        </div>
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.total_projects)"
            label="Total projects"
          />
        </div>
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.active_projects)"
            label="Active projects"
          />
        </div>
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.archived_projects)"
            label="Archived projects"
          />
        </div>
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.deleted_projects)"
            label="Deleted projects"
          />
        </div>
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.pending_invitations)"
            label="Pending invitations"
          />
        </div>
        <div class="rounded-lg border border-line bg-surface p-4">
          <StatTile
            :value="String(overview.active_invitations)"
            label="Tracked invitations"
          />
        </div>
      </div>
    </div>

    <div class="mt-8 grid gap-6 xl:grid-cols-3">
      <section class="min-w-0">
        <h2 class="text-14 font-semibold text-ink">
          Recent users
        </h2>
        <div class="mt-3 overflow-hidden rounded-lg border border-line bg-surface">
          <SkeletonBlock
            v-if="users.isPending.value"
            height="220px"
            rounded="0"
          />
          <ErrorState
            v-else-if="users.isError.value"
            :error="users.error.value"
            :retry="() => users.refetch()"
          />
          <EmptyState
            v-else-if="recentUsers.length === 0"
            message="No users found."
          />
          <RouterLink
            v-for="user in recentUsers"
            v-else
            :key="user.id"
            :to="{ name: 'admin.user', params: { userId: user.id } }"
            class="block border-b border-line px-4 py-3 last:border-b-0 hover:bg-[#FBFBFA] focus-ring"
          >
            <div class="truncate text-14 font-medium text-ink">
              {{ user.display_name }}
            </div>
            <div class="truncate text-13 text-muted">
              {{ user.email }} · {{ date(user.created_at) }}
            </div>
          </RouterLink>
        </div>
      </section>

      <section class="min-w-0">
        <h2 class="text-14 font-semibold text-ink">
          Recent projects
        </h2>
        <div class="mt-3 overflow-hidden rounded-lg border border-line bg-surface">
          <SkeletonBlock
            v-if="projects.isPending.value"
            height="220px"
            rounded="0"
          />
          <ErrorState
            v-else-if="projects.isError.value"
            :error="projects.error.value"
            :retry="() => projects.refetch()"
          />
          <EmptyState
            v-else-if="recentProjects.length === 0"
            message="No projects found."
          />
          <RouterLink
            v-for="project in recentProjects"
            v-else
            :key="project.id"
            :to="{ name: 'admin.project', params: { projectId: project.id } }"
            class="block border-b border-line px-4 py-3 last:border-b-0 hover:bg-[#FBFBFA] focus-ring"
          >
            <div class="truncate text-14 font-medium text-ink">
              {{ project.name }}
            </div>
            <div class="truncate text-13 text-muted">
              {{ presentLabel(project.status) }} · {{ project.member_count }} members
            </div>
          </RouterLink>
        </div>
      </section>

      <section class="min-w-0">
        <h2 class="text-14 font-semibold text-ink">
          Recent audit activity
        </h2>
        <div class="mt-3 overflow-hidden rounded-lg border border-line bg-surface">
          <SkeletonBlock
            v-if="audit.isPending.value"
            height="220px"
            rounded="0"
          />
          <ErrorState
            v-else-if="audit.isError.value"
            :error="audit.error.value"
            :retry="() => audit.refetch()"
          />
          <EmptyState
            v-else-if="recentAudit.length === 0"
            message="No audit activity found."
          />
          <div
            v-for="event in recentAudit"
            v-else
            :key="event.id"
            class="border-b border-line px-4 py-3 last:border-b-0"
          >
            <div class="truncate text-14 font-medium text-ink">
              {{ presentAuditAction(event.action, event.entity_type) }}
            </div>
            <div class="truncate text-13 text-muted">
              {{ event.project_name ?? "No project" }} · {{ date(event.at) }}
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

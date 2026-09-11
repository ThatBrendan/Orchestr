<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useAdminProject } from "@/composables/useAdmin";
import { useMoney } from "@/composables/useMoney";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import StatTile from "@/components/ui/StatTile.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId ?? ""));
const { project, members, audit, health } = useAdminProject(projectId);
const { format } = useMoney();

function date(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value)) : "-";
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-6 md:px-8 md:py-8">
    <RouterLink
      :to="{ name: 'admin.projects' }"
      class="text-13 font-medium text-muted hover:text-ink focus-ring"
    >
      Back to projects
    </RouterLink>

    <SkeletonBlock
      v-if="project.isPending.value"
      class="mt-5"
      height="180px"
      rounded="0.5rem"
    />
    <ErrorState
      v-else-if="project.isError.value"
      class="mt-5"
      :error="project.error.value"
      :retry="() => project.refetch()"
    />
    <section
      v-else-if="project.data.value"
      class="mt-5 rounded-lg border border-line bg-surface p-5"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <h1 class="truncate font-display text-[26px] font-semibold tracking-tight">
            {{ project.data.value.name }}
          </h1>
          <p class="mt-1 text-13 text-muted">
            {{ project.data.value.id }}
          </p>
        </div>
        <StatusBadge :label="project.data.value.deleted_at ? 'deleted' : project.data.value.status" />
      </div>
      <dl class="mt-5 grid gap-4 text-14 sm:grid-cols-4">
        <div>
          <dt class="text-muted">
            Created
          </dt><dd class="mt-1 font-medium text-ink">
            {{ date(project.data.value.created_at) }}
          </dd>
        </div>
        <div>
          <dt class="text-muted">
            Updated
          </dt><dd class="mt-1 font-medium text-ink">
            {{ date(project.data.value.updated_at) }}
          </dd>
        </div>
        <div>
          <dt class="text-muted">
            Timezone
          </dt><dd class="mt-1 font-medium text-ink">
            {{ project.data.value.timezone }}
          </dd>
        </div>
        <div>
          <dt class="text-muted">
            Creator
          </dt><dd class="mt-1 font-medium text-ink">
            {{ project.data.value.created_by_display_name ?? project.data.value.created_by_email ?? "-" }}
          </dd>
        </div>
      </dl>
    </section>

    <div
      v-if="project.data.value"
      class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4"
    >
      <div class="rounded-lg border border-line bg-surface p-4">
        <StatTile
          :value="String(project.data.value.active_member_count)"
          label="Active members"
        />
      </div>
      <div class="rounded-lg border border-line bg-surface p-4">
        <StatTile
          :value="String(project.data.value.commitment_count)"
          label="Commitments"
        />
      </div>
      <div class="rounded-lg border border-line bg-surface p-4">
        <StatTile
          :value="format(project.data.value.total_cost_minor, project.data.value.currency)"
          label="Total planned"
        />
      </div>
      <div class="rounded-lg border border-line bg-surface p-4">
        <StatTile
          :value="format(project.data.value.gross_paid_minor, project.data.value.currency)"
          label="Gross paid"
        />
      </div>
    </div>

    <section class="mt-8">
      <h2 class="text-14 font-semibold text-ink">
        Planning health
      </h2>
      <div class="mt-3 rounded-lg border border-line bg-surface p-4">
        <SkeletonBlock
          v-if="health.isPending.value"
          height="72px"
          rounded="0.5rem"
        />
        <ErrorState
          v-else-if="health.isError.value"
          :error="health.error.value"
          :retry="() => health.refetch()"
        />
        <div
          v-else-if="health.data.value"
          class="grid gap-4 text-14 sm:grid-cols-5"
        >
          <div>
            <dt class="text-muted">
              Status
            </dt><dd class="mt-1">
              <StatusBadge :label="health.data.value.status" />
            </dd>
          </div>
          <div>
            <dt class="text-muted">
              Attention
            </dt><dd class="mt-1 font-medium text-ink">
              {{ health.data.value.attention_count }}
            </dd>
          </div>
          <div>
            <dt class="text-muted">
              Blockers
            </dt><dd class="mt-1 font-medium text-ink">
              {{ health.data.value.blocker_count }}
            </dd>
          </div>
          <div>
            <dt class="text-muted">
              Warnings
            </dt><dd class="mt-1 font-medium text-ink">
              {{ health.data.value.warning_count }}
            </dd>
          </div>
          <div>
            <dt class="text-muted">
              Info
            </dt><dd class="mt-1 font-medium text-ink">
              {{ health.data.value.info_count }}
            </dd>
          </div>
        </div>
        <EmptyState
          v-else
          message="No planning-health summary found."
        />
      </div>
    </section>

    <div class="mt-8 grid gap-6 xl:grid-cols-2">
      <section>
        <h2 class="text-14 font-semibold text-ink">
          Members
        </h2>
        <div class="mt-3 overflow-x-auto rounded-lg border border-line bg-surface">
          <SkeletonBlock
            v-if="members.isPending.value"
            height="260px"
            rounded="0"
          />
          <ErrorState
            v-else-if="members.isError.value"
            :error="members.error.value"
            :retry="() => members.refetch()"
          />
          <EmptyState
            v-else-if="(members.data.value ?? []).length === 0"
            message="No members found."
          />
          <table
            v-else
            class="w-full min-w-[640px] text-left text-14"
          >
            <thead class="border-b border-line text-12 uppercase text-muted">
              <tr>
                <th class="px-4 py-3 font-medium">
                  Member
                </th><th class="px-4 py-3 font-medium">
                  Email
                </th><th class="px-4 py-3 font-medium">
                  Role
                </th><th class="px-4 py-3 font-medium">
                  Status
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-line">
              <tr
                v-for="member in members.data.value ?? []"
                :key="member.id"
              >
                <td class="px-4 py-3 font-medium text-ink">
                  {{ member.display_name }}
                </td>
                <td class="px-4 py-3 text-ink-soft">
                  {{ member.email ?? "-" }}
                </td>
                <td class="px-4 py-3 text-ink-soft">
                  {{ member.role }}
                </td>
                <td class="px-4 py-3">
                  <StatusBadge :label="member.status" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 class="text-14 font-semibold text-ink">
          Recent audit activity
        </h2>
        <div class="mt-3 overflow-hidden rounded-lg border border-line bg-surface">
          <SkeletonBlock
            v-if="audit.isPending.value"
            height="260px"
            rounded="0"
          />
          <ErrorState
            v-else-if="audit.isError.value"
            :error="audit.error.value"
            :retry="() => audit.refetch()"
          />
          <EmptyState
            v-else-if="(audit.data.value ?? []).length === 0"
            message="No audit activity found."
          />
          <div
            v-for="event in audit.data.value ?? []"
            v-else
            :key="event.id"
            class="border-b border-line px-4 py-3 last:border-b-0"
          >
            <div class="text-14 font-medium text-ink">
              {{ event.action }} {{ event.entity_type }}
            </div>
            <div class="mt-0.5 text-13 text-muted">
              {{ event.actor_email ?? "System" }} · {{ date(event.at) }}
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

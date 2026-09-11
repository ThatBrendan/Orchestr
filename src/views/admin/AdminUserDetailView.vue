<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useAdminUser } from "@/composables/useAdmin";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import { presentAuditAction, presentLabel } from "@/lib/presentation";

const route = useRoute();
const userId = computed(() => String(route.params.userId ?? ""));
const { user, memberships, audit } = useAdminUser(userId);

function date(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value)) : "-";
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-6 md:px-8 md:py-8">
    <RouterLink
      :to="{ name: 'admin.users' }"
      class="text-13 font-medium text-muted hover:text-ink focus-ring"
    >
      Back to users
    </RouterLink>

    <SkeletonBlock
      v-if="user.isPending.value"
      class="mt-5"
      height="150px"
      rounded="0.5rem"
    />
    <ErrorState
      v-else-if="user.isError.value"
      class="mt-5"
      :error="user.error.value"
      :retry="() => user.refetch()"
    />
    <section
      v-else-if="user.data.value"
      class="mt-5 rounded-lg border border-line bg-surface p-5"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <h1 class="truncate font-display text-[26px] font-semibold tracking-tight">
            {{ user.data.value.display_name }}
          </h1>
          <p class="mt-1 text-14 text-ink-soft">
            {{ user.data.value.email }}
          </p>
          <p class="mt-1 text-13 text-muted">
            {{ user.data.value.id }}
          </p>
        </div>
        <StatusBadge
          :label="user.data.value.platform_role"
          :tone="user.data.value.platform_role === 'admin' ? 'accent' : 'neutral'"
        />
      </div>
      <dl class="mt-5 grid gap-4 text-14 sm:grid-cols-3">
        <div>
          <dt class="text-muted">
            Joined
          </dt><dd class="mt-1 font-medium text-ink">
            {{ date(user.data.value.created_at) }}
          </dd>
        </div>
        <div>
          <dt class="text-muted">
            Timezone
          </dt><dd class="mt-1 font-medium text-ink">
            {{ user.data.value.timezone }}
          </dd>
        </div>
        <div>
          <dt class="text-muted">
            Currency
          </dt><dd class="mt-1 font-medium text-ink">
            {{ user.data.value.default_currency }}
          </dd>
        </div>
      </dl>
    </section>

    <div class="mt-8 grid gap-6 xl:grid-cols-2">
      <section>
        <h2 class="text-14 font-semibold text-ink">
          Memberships
        </h2>
        <div class="mt-3 overflow-x-auto rounded-lg border border-line bg-surface">
          <SkeletonBlock
            v-if="memberships.isPending.value"
            height="260px"
            rounded="0"
          />
          <ErrorState
            v-else-if="memberships.isError.value"
            :error="memberships.error.value"
            :retry="() => memberships.refetch()"
          />
          <EmptyState
            v-else-if="(memberships.data.value ?? []).length === 0"
            message="No memberships found."
          />
          <table
            v-else
            class="w-full min-w-[560px] text-left text-14"
          >
            <thead class="border-b border-line text-12 uppercase text-muted">
              <tr>
                <th class="px-4 py-3 font-medium">
                  Project
                </th><th class="px-4 py-3 font-medium">
                  Role
                </th><th class="px-4 py-3 font-medium">
                  Status
                </th><th class="px-4 py-3 font-medium">
                  Joined
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-line">
              <tr
                v-for="m in memberships.data.value ?? []"
                :key="m.member_id"
              >
                <td class="px-4 py-3">
                  <RouterLink
                    :to="{ name: 'admin.project', params: { projectId: m.project_id } }"
                    class="font-medium text-ink focus-ring"
                  >
                    {{ m.project_name }}
                  </RouterLink>
                </td>
                <td class="px-4 py-3 text-ink-soft">
                  {{ presentLabel(m.role) }}
                </td>
                <td class="px-4 py-3">
                  <StatusBadge :label="presentLabel(m.status)" />
                </td>
                <td class="px-4 py-3 text-muted">
                  {{ date(m.joined_at) }}
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
              {{ presentAuditAction(event.action, event.entity_type) }}
            </div>
            <div class="mt-0.5 text-13 text-muted">
              {{ event.project_name ?? "No project" }} · {{ date(event.at) }}
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

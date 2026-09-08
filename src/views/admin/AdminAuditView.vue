<script setup lang="ts">
import { ref } from "vue";
import { useAdminAudit } from "@/composables/useAdmin";
import EmptyState from "@/components/ui/EmptyState.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";

const search = ref("");
const { events, isPending, isError, error, refetch } = useAdminAudit(search);

function dateTime(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-6 md:px-8 md:py-8">
    <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">Audit</h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">Immutable platform-wide audit activity.</p>
      </div>
      <input
        v-model="search"
        type="search"
        class="h-10 w-full rounded-lg border border-line bg-surface px-3 text-14 focus-ring sm:w-72"
        placeholder="Search audit"
      />
    </div>

    <div class="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
      <SkeletonBlock v-if="isPending" height="420px" rounded="0" />
      <ErrorState v-else-if="isError" :error="error" :retry="() => refetch()" />
      <EmptyState v-else-if="events.length === 0" message="No audit activity found." />
      <table v-else class="w-full min-w-[980px] text-left text-14">
        <thead class="border-b border-line text-12 uppercase text-muted">
          <tr>
            <th class="px-4 py-3 font-medium">Time</th>
            <th class="px-4 py-3 font-medium">Actor</th>
            <th class="px-4 py-3 font-medium">Action</th>
            <th class="px-4 py-3 font-medium">Entity</th>
            <th class="px-4 py-3 font-medium">Project</th>
            <th class="px-4 py-3 font-medium">Request</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          <tr v-for="event in events" :key="event.id">
            <td class="px-4 py-3 text-muted">{{ dateTime(event.at) }}</td>
            <td class="px-4 py-3 text-ink-soft">{{ event.actor_display_name ?? event.actor_email ?? "System" }}</td>
            <td class="px-4 py-3"><StatusBadge :label="event.action" /></td>
            <td class="px-4 py-3 text-ink-soft">{{ event.entity_type }} · {{ event.entity_id }}</td>
            <td class="px-4 py-3 text-ink-soft">{{ event.project_name ?? "-" }}</td>
            <td class="px-4 py-3 text-muted">{{ event.request_id ?? "-" }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

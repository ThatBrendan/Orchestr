<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useMemberDirectory } from "@/composables/useProject";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import AppAvatar from "@/components/ui/AppAvatar.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";

// Read-only member list — v_member_directory backend is ready. Managing members
// (invite / role changes / removal) is a later pass.
const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { members, isPending, isError, error, refetch } = useMemberDirectory(projectId);

const roleTone = (r: string) => (r === "organizer" ? "accent" : r === "viewer" ? "neutral" : "neutral");
</script>

<template>
  <div class="fade-in">
    <div v-if="isPending" class="space-y-2">
      <SkeletonBlock v-for="i in 4" :key="i" height="56px" rounded="0.5rem" />
    </div>
    <ErrorState v-else-if="isError" :error="error" :retry="() => refetch()" />
    <template v-else>
      <p class="text-14 mb-4 text-ink-soft">{{ members.length }} {{ members.length === 1 ? "person" : "people" }}</p>
      <div class="border rounded-xl divide-y border-line bg-surface">
        <div v-for="m in members" :key="m.member_id" class="flex items-center gap-3.5 px-4 py-3.5">
          <AppAvatar :name="m.display_name" :url="m.avatar_url" :size="36" />
          <div class="min-w-0 flex-1">
            <div class="text-14 font-medium">{{ m.display_name }}</div>
            <div class="text-13 text-muted capitalize">{{ m.role }}</div>
          </div>
          <StatusBadge v-if="m.role === 'organizer'" label="Organizer" :tone="roleTone(m.role)" />
        </div>
      </div>
      <p class="mt-4 text-13 text-muted">Inviting people and changing roles arrives in a later pass.</p>
    </template>
  </div>
</template>

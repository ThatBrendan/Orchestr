<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink } from "vue-router";
import { useGlobalPeople } from "@/composables/useGlobalPeople";
import { useMyProjects } from "@/composables/useProjects";
import type { GlobalPerson } from "@/types/derived";
import PageContainer from "@/components/ui/PageContainer.vue";
import AppAvatar from "@/components/ui/AppAvatar.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { presentLabel } from "@/lib/presentation";

const { people, isPending, isError, error, refetch } = useGlobalPeople();
const { projects } = useMyProjects();
const search = ref("");
const selectedProject = ref("");
const selectedPerson = ref<GlobalPerson | null>(null);

const filteredPeople = computed(() => {
  const term = search.value.trim().toLowerCase();
  return people.value.filter((person) => {
    const matchesSearch = !term || person.display_name.toLowerCase().includes(term);
    const matchesProject = !selectedProject.value || person.projects.some((project) => project.project_id === selectedProject.value);
    return matchesSearch && matchesProject;
  });
});

function projectLabel(count: number): string {
  return `${count} shared ${count === 1 ? "project" : "projects"}`;
}

function roleLabel(role: string): string {
  return presentLabel(role);
}

function roleTone(role: string) {
  return role === "organizer" ? "accent" : "neutral";
}
</script>

<template>
  <PageContainer width="lg">
    <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
      <div>
        <h1 class="font-display text-[26px] font-semibold tracking-tight">
          People
        </h1>
        <p class="mt-1.5 text-14.5 text-ink-soft">
          Everyone you plan with across your projects.
        </p>
      </div>
      <div class="grid gap-2 sm:grid-cols-2 md:w-[30rem]">
        <input
          v-model="search"
          type="search"
          placeholder="Search people..."
          class="border rounded-lg px-3 py-2 text-14 focus-ring border-line bg-surface"
        >
        <select
          v-model="selectedProject"
          class="border rounded-lg px-3 py-2 text-14 focus-ring border-line bg-surface"
        >
          <option value="">
            All projects
          </option>
          <option
            v-for="project in projects"
            :key="project.project_id"
            :value="project.project_id"
          >
            {{ project.name }}
          </option>
        </select>
      </div>
    </div>

    <div
      v-if="isPending"
      class="mt-6 space-y-2"
    >
      <SkeletonBlock
        v-for="i in 5"
        :key="i"
        height="72px"
        rounded="0.75rem"
      />
    </div>
    <ErrorState
      v-else-if="isError"
      class="mt-6"
      :error="error"
      :retry="() => refetch()"
    />
    <EmptyState
      v-else-if="people.length === 0"
      class="mt-6"
      message="No people yet. Project members will appear here once you start planning with others."
    />
    <EmptyState
      v-else-if="filteredPeople.length === 0"
      class="mt-6"
      message="No people match those filters."
    />

    <div
      v-else
      class="mt-6 divide-y rounded-xl border border-line bg-surface"
    >
      <button
        v-for="person in filteredPeople"
        :key="person.person_key"
        class="flex w-full items-center gap-3.5 px-4 py-3.5 text-left hover:bg-[#FBFBFA] focus-ring"
        @click="selectedPerson = person"
      >
        <AppAvatar
          :name="person.display_name"
          :url="person.avatar_url"
          :size="40"
        />
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-14 font-medium">{{ person.display_name }}</span>
            <StatusBadge
              v-if="person.is_current_user"
              label="You"
              tone="accent"
            />
            <StatusBadge
              v-if="!person.user_id"
              label="Name-only member"
              tone="neutral"
            />
          </div>
          <div class="mt-0.5 text-13 text-muted">
            {{ projectLabel(person.project_count) }}
          </div>
          <div class="mt-1 flex flex-wrap gap-1.5">
            <span
              v-for="project in person.projects.slice(0, 3)"
              :key="project.project_id + project.member_id"
              class="rounded-full border border-line px-2 py-0.5 text-12 text-ink-soft"
            >
              {{ project.project_name }}
            </span>
            <span
              v-if="person.projects.length > 3"
              class="px-2 py-0.5 text-12 text-muted"
            >+{{ person.projects.length - 3 }}</span>
          </div>
        </div>
      </button>
    </div>

    <div
      v-if="selectedPerson"
      class="fixed inset-0 z-40 bg-black/20 px-4 py-6"
      @click.self="selectedPerson = null"
    >
      <aside class="ml-auto flex h-full w-full max-w-md flex-col rounded-xl border border-line bg-surface shadow-xl">
        <div class="flex items-start gap-3 border-b border-line p-5">
          <AppAvatar
            :name="selectedPerson.display_name"
            :url="selectedPerson.avatar_url"
            :size="44"
          />
          <div class="min-w-0 flex-1">
            <h2 class="font-display text-[21px] font-semibold tracking-tight">
              {{ selectedPerson.display_name }}
            </h2>
            <div class="mt-1 flex flex-wrap gap-2">
              <StatusBadge
                v-if="selectedPerson.is_current_user"
                label="You"
                tone="accent"
              />
              <StatusBadge
                v-if="!selectedPerson.user_id"
                label="Name-only member"
                tone="neutral"
              />
            </div>
          </div>
          <AppButton
            variant="secondary"
            size="sm"
            @click="selectedPerson = null"
          >
            Close
          </AppButton>
        </div>
        <div class="flex-1 overflow-y-auto p-5">
          <h3 class="text-13 font-semibold uppercase tracking-wide text-ink-soft">
            Shared projects
          </h3>
          <div class="mt-3 space-y-2">
            <RouterLink
              v-for="project in selectedPerson.projects"
              :key="project.project_id + project.member_id"
              :to="{ name: 'project.people', params: { projectId: project.project_id } }"
              class="block rounded-lg border border-line px-3 py-2.5 hover:bg-[#F6F6F4] focus-ring"
            >
              <div class="flex items-center justify-between gap-3">
                <span class="text-14 font-medium">{{ project.project_name }}</span>
                <StatusBadge
                  :label="roleLabel(project.role)"
                  :tone="roleTone(project.role)"
                />
              </div>
              <div
                v-if="project.status !== 'active'"
                class="mt-1 text-13 capitalize text-muted"
              >
                {{ presentLabel(project.status) }}
              </div>
            </RouterLink>
          </div>
        </div>
      </aside>
    </div>
  </PageContainer>
</template>

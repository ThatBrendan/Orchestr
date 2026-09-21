<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useDecisions } from "@/composables/useDecisions";
import { useProjectTime } from "@/composables/useProjectTime";
import AppButton from "@/components/ui/AppButton.vue";
import DecisionFormDialog from "@/components/decisions/DecisionFormDialog.vue";
const route = useRoute(), router = useRouter(), { project, role } = useProjectContext();
const projectId = computed(() => String(route.params.projectId));
const { list, refresh } = useDecisions(projectId), creating = ref(false);
const canCreate = computed(() => (role.value === "organizer" || role.value === "member") && project.value?.status !== "archived");
async function saved(id: string) { creating.value = false; await refresh(); await router.push({ name: "project.decision", params: { projectId: projectId.value, decisionId: id } }); }
</script>
<template>
  <section class="py-6 space-y-5">
    <div class="flex items-center justify-between gap-3">
      <h2 class="text-xl font-semibold">
        Decisions
      </h2><AppButton
        v-if="canCreate"
        @click="creating = true"
      >
        New decision
      </AppButton>
    </div>
    <p
      v-if="list.isPending.value"
      role="status"
    >
      Loading decisions…
    </p>
    <div
      v-else-if="list.error.value"
      role="alert"
    >
      <p>{{ list.error.value.message }}</p><AppButton
        variant="secondary"
        @click="list.refetch()"
      >
        Retry
      </AppButton>
    </div>
    <div
      v-else-if="!list.data.value?.length"
      class="rounded-lg border border-line p-6"
    >
      <p class="font-medium">
        No decisions yet.
      </p><p class="mt-2 text-muted">
        Create a decision when the group needs to choose between options.
      </p>
    </div>
    <RouterLink
      v-for="decision in list.data.value"
      :key="decision.id"
      :to="{ name: 'project.decision', params: { projectId, decisionId: decision.id } }"
      class="block rounded-lg border border-line p-4 space-y-2 focus-ring"
    >
      <h3 class="font-medium break-words">
        {{ decision.title }}
      </h3>
      <p class="text-13 text-muted">
        {{ decision.options.length }} options · {{ decision.vote_count }} {{ decision.vote_count === 1 ? 'vote' : 'votes' }}
      </p>
      <p
        v-if="decision.status === 'resolved'"
        class="text-14"
      >
        Resolved — {{ decision.options.find(o => o.id === decision.resolved_option_id)?.title }} selected
      </p>
      <p
        v-else-if="decision.voting_deadline"
        class="text-14"
      >
        {{ decision.deadline_reached ? 'Voting closed' : 'Voting closes' }} {{ useProjectTime(project?.timezone ?? 'UTC').dateTime(decision.voting_deadline) }} · {{ project?.timezone }}
      </p>
      <p
        v-else
        class="text-14"
      >
        Open · No voting deadline
      </p>
    </RouterLink>
    <DecisionFormDialog
      v-if="creating"
      :project-id="projectId"
      :currency="project?.currency ?? 'GBP'"
      :timezone="project?.timezone ?? 'UTC'"
      @close="creating = false"
      @saved="saved"
    />
  </section>
</template>

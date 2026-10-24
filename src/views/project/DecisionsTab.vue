<script setup lang="ts">
import { useExecutionDialogFocus } from "@/composables/useExecutionDialogFocus";
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { useDecisions } from "@/composables/useDecisions";
import { useProjectTime } from "@/composables/useProjectTime";
import AppButton from "@/components/ui/AppButton.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import DecisionFormDialog from "@/components/decisions/DecisionFormDialog.vue";
const route = useRoute(), router = useRouter(), { project, role } = useProjectContext();
const projectId = computed(() => String(route.params.projectId));
const { list, refresh } = useDecisions(projectId), creating = ref(false);
const canCreate = computed(() => (role.value === "organizer" || role.value === "member") && project.value?.status !== "archived");
const groups = computed(() => [
  { label: "Open decisions", items: (list.data.value ?? []).filter(d => d.status === "open") },
  { label: "Resolved decisions", items: (list.data.value ?? []).filter(d => d.status === "resolved") },
].filter(group => group.items.length));
async function saved(id: string) { creating.value = false; await refresh(); await router.push({ name: "project.decision", params: { projectId: projectId.value, decisionId: id } }); }
const focusFallback = ref<HTMLElement | null>(null);
useExecutionDialogFocus(creating, focusFallback);
</script>
<template>
  <section class="space-y-6 max-w-4xl fade-in">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2
        ref="focusFallback"
        tabindex="-1"
        class="text-section-heading focus-ring"
      >
        Decisions
      </h2>
      <AppButton
        v-if="canCreate"
        @click="creating = true"
      >
        New decision
      </AppButton>
    </div>
    <div
      v-if="list.isPending.value"
      class="space-y-3"
      role="status"
      aria-label="Loading decisions"
    >
      <SkeletonBlock
        v-for="i in 3"
        :key="i"
        height="112px"
        rounded="0.75rem"
      />
    </div>
    <ErrorState
      v-else-if="list.error.value"
      :error="list.error.value"
      :retry="() => list.refetch()"
    />
    <div
      v-else-if="!list.data.value?.length"
      class="rounded-xl border border-line bg-surface p-5"
    >
      <p class="font-medium">
        No decisions yet.
      </p><p class="mt-2 text-sm text-muted">
        Create a decision when the group needs to choose between options.
      </p>
    </div>
    <template v-else>
      <section
        v-for="group in groups"
        :key="group.label"
        :aria-label="group.label"
        class="space-y-3"
      >
        <h3 class="text-sm font-semibold text-ink-soft">
          {{ group.label }}
        </h3>
        <div class="rounded-xl border border-line bg-surface divide-y divide-line">
          <RouterLink
            v-for="decision in group.items"
            :key="decision.id"
            :to="{ name: 'project.decision', params: { projectId, decisionId: decision.id } }"
            class="block p-4 sm:p-5 first:rounded-t-xl last:rounded-b-xl hover:bg-surface-subtle focus-ring"
          >
            <div class="flex items-start gap-3">
              <span
                class="mt-1.5 h-2 w-2 shrink-0 rounded-full"
                :class="decision.status === 'resolved' ? 'bg-success' : 'bg-brand'"
                aria-hidden="true"
              />
              <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
                <h4 class="text-card-heading font-semibold">
                  {{ decision.title }}
                </h4>
                <p
                  v-if="decision.status === 'resolved'"
                  class="mt-2 text-sm text-success"
                >
                  Resolved — {{ decision.options.find(o => o.id === decision.resolved_option_id)?.title }} selected
                </p>
                <p
                  v-else-if="decision.voting_deadline"
                  class="mt-2 text-sm text-ink-soft"
                >
                  {{ decision.deadline_reached ? 'Voting closed' : 'Voting closes' }} {{ useProjectTime(project?.timezone ?? 'UTC').dateTime(decision.voting_deadline) }} · {{ project?.timezone }}
                </p>
                <p
                  v-else
                  class="mt-2 text-sm text-ink-soft"
                >
                  Open · No voting deadline
                </p>
                <p class="mt-2 text-meta text-muted">
                  {{ decision.options.length }} options · {{ decision.vote_count }} {{ decision.vote_count === 1 ? 'vote' : 'votes' }}<span v-if="decision.my_option_id"> · You voted</span>
                </p>
                <span
                  class="mt-2 inline-flex min-h-6 items-center text-sm font-medium"
                  :class="decision.status === 'resolved' ? 'text-ink-soft' : 'text-brand'"
                >{{ decision.status === 'resolved' ? 'View result' : decision.can_vote ? (decision.my_option_id ? 'Review your vote' : 'Vote on this decision') : 'View decision' }} <span
                  aria-hidden="true"
                  class="ml-2"
                >→</span></span>
              </div>
            </div>
          </RouterLink>
        </div>
      </section>
    </template>
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

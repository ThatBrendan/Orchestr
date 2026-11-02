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
import AppIcon from "@/components/ui/AppIcon.vue";
import type { Decision } from "@/types/decisions";
const route = useRoute(), router = useRouter(), { project, role } = useProjectContext();
const projectId = computed(() => String(route.params.projectId));
const { list, refresh } = useDecisions(projectId), creating = ref(false);
const canCreate = computed(() => (role.value === "organizer" || role.value === "member") && project.value?.status !== "archived");
function formatDeadline(deadline: string) {
 return useProjectTime(project.value?.timezone ?? "UTC").dateTime(deadline);
}
const groups = computed(() => [
  { label: "Open decisions", items: (list.data.value ?? []).filter(d => d.status === "open") },
  { label: "Resolved decisions", items: (list.data.value ?? []).filter(d => d.status === "resolved") },
].filter(group => group.items.length));
const summary = computed(() => {
 const rows = list.data.value ?? [];
 const open = rows.filter(decision => decision.status === "open").length;
 const resolved = rows.filter(decision => decision.status === "resolved").length;
 const awaitingVote = rows.filter(decision => decision.status === "open" && decision.can_vote && !decision.my_option_id && !decision.deadline_reached).length;
 return { open, resolved, awaitingVote };
});
function optionPercent(decision: Decision, optionId: string) {
 const option = decision.options.find(item => item.id === optionId);
 return decision.vote_count > 0 && option ? Math.round((option.vote_count / decision.vote_count) * 100) : 0;
}
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
      v-if="!list.isPending.value && !list.error.value && summary.open + summary.resolved > 0"
      class="flex flex-wrap gap-2"
      aria-label="Decision summary"
    >
      <span class="inline-flex min-h-9 items-center gap-2 rounded-full border border-line bg-surface px-3 text-sm">
        <span class="font-semibold text-brand">{{ summary.open }}</span>
        <span class="text-muted">{{ summary.open === 1 ? "Open decision" : "Open decisions" }}</span>
      </span>
      <span class="inline-flex min-h-9 items-center gap-2 rounded-full border border-line bg-surface px-3 text-sm">
        <span class="font-semibold text-success">{{ summary.resolved }}</span>
        <span class="text-muted">Resolved</span>
      </span>
      <span
        v-if="summary.awaitingVote"
        class="inline-flex min-h-9 items-center gap-2 rounded-full border border-brand-soft bg-brand-soft px-3 text-sm text-brand"
      >
        <span class="font-semibold">{{ summary.awaitingVote }}</span>
        <span>awaiting your vote</span>
      </span>
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
        <div class="flex items-center justify-between gap-3">
          <h3 class="text-section-heading text-base font-semibold">
            {{ group.label }}
          </h3>
          <span class="text-meta text-muted">
            {{ group.items.length }} {{ group.items.length === 1 ? "decision" : "decisions" }}
          </span>
        </div>
        <div class="grid gap-3">
          <RouterLink
            v-for="decision in group.items"
            :key="decision.id"
            :to="{ name: 'project.decision', params: { projectId, decisionId: decision.id } }"
            class="block min-w-0 rounded-xl border bg-surface p-4 sm:p-5 hover:bg-surface-subtle focus-ring"
            :class="decision.status === 'resolved' ? 'border-success/20' : 'border-line'"
          >
            <div class="flex min-w-0 items-start gap-3">
              <span
                class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg"
                :class="decision.status === 'resolved' ? 'bg-success-soft text-success' : 'bg-brand-soft text-brand'"
                aria-hidden="true"
              >
                <AppIcon
                  :name="decision.status === 'resolved' ? 'checkCircle' : 'circleDot'"
                  :size="18"
                />
              </span>
              <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
                <div
                  v-if="decision.status === 'resolved'"
                  class="mb-1 text-meta font-medium text-success"
                >
                  Resolved
                </div>
                <h4 class="text-card-heading font-semibold text-ink">
                  {{ decision.title }}
                </h4>
                <p
                  v-if="decision.description"
                  class="mt-1 line-clamp-2 text-sm text-ink-soft"
                >
                  {{ decision.description }}
                </p>
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
                  <span class="inline-flex items-center gap-1.5">
                    <AppIcon
                      name="clock"
                      :size="15"
                    />
                    {{ decision.deadline_reached ? "Voting closed" : "Voting closes" }}
                    {{ formatDeadline(decision.voting_deadline) }}
                  </span>
                </p>
                <p
                  v-else
                  class="mt-2 text-sm text-ink-soft"
                >
                  Open · No voting deadline
                </p>
                <p class="mt-2 text-meta text-muted">
                  {{ decision.vote_count }} {{ decision.vote_count === 1 ? "vote" : "votes" }}
                  <span v-if="decision.status === 'open' && decision.my_option_id"> · You voted</span>
                  <span v-else-if="decision.status === 'open' && decision.can_vote"> · Vote needed</span>
                </p>
                <div
                  v-if="decision.status === 'open' && decision.options.length"
                  class="mt-3 space-y-2"
                >
                  <div
                    v-for="option in decision.options"
                    :key="option.id"
                    class="rounded-lg border border-line px-3 py-2"
                  >
                    <div class="flex items-center justify-between gap-3 text-sm">
                      <span class="min-w-0 break-words text-ink-soft">{{ option.title }}</span>
                      <span class="shrink-0 text-meta text-muted">{{ option.vote_count }} {{ option.vote_count === 1 ? "vote" : "votes" }}</span>
                    </div>
                    <div
                      class="mt-2 h-1.5 overflow-hidden rounded-full bg-line/70"
                      role="progressbar"
                      :aria-label="`${option.title}: ${option.vote_count} votes`"
                      aria-valuemin="0"
                      aria-valuemax="100"
                      :aria-valuenow="optionPercent(decision, option.id)"
                    >
                      <div
                        class="h-full rounded-full bg-brand"
                        :style="{ width: `${optionPercent(decision, option.id)}%` }"
                      />
                    </div>
                  </div>
                </div>
                <span
                  class="mt-3 inline-flex min-h-8 items-center text-sm font-medium"
                  :class="decision.status === 'resolved' ? 'text-ink-soft' : 'text-brand'"
                >
                  {{ decision.status === 'resolved' ? 'View result' : decision.can_vote ? (decision.my_option_id ? 'Review your vote' : 'Vote on this decision') : 'View decision' }}
                  <AppIcon
                    name="arrowRight"
                    :size="16"
                    class="ml-1.5"
                  />
                </span>
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

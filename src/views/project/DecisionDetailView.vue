<script setup lang="ts">
import { useExecutionDialogFocus } from "@/composables/useExecutionDialogFocus";
import ResourceComments from "@/components/comments/ResourceComments.vue";
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useQuery } from "@tanstack/vue-query";
import { useProjectContext } from "@/composables/useProjectContext";
import { useDecisions } from "@/composables/useDecisions";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { listAreas } from "@/services/items";
import { voteDecision, resolveDecision, convertDecision, deleteDecision } from "@/services/decisions";
import { toAppError } from "@/lib/errors";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppModal from "@/components/ui/AppModal.vue";
import DecisionFormDialog from "@/components/decisions/DecisionFormDialog.vue";
import ShareLinkDialog from "@/components/sharing/ShareLinkDialog.vue";
const route = useRoute(), router = useRouter(), { project } = useProjectContext(), money = useMoney();
const projectId = computed(() => String(route.params.projectId)), id = computed(() => String(route.params.decisionId));
const { list, refresh } = useDecisions(projectId, id), decision = computed(() => list.data.value?.[0]);
const selected = computed(() => decision.value?.options.find(o => o.id === decision.value?.resolved_option_id));
const leading = computed(() => Math.max(0, ...(decision.value?.options.map(o => o.vote_count) ?? [])));
const dialog = ref<"edit" | "resolve" | "convert" | "delete" | "share" | null>(null);
const choice = ref(""), category = ref(""), activityType = ref("other"), busy = ref(false), error = ref("");
const areas = useQuery({ queryKey: computed(() => ["project", projectId.value, "decision-conversion-categories"]), queryFn: () => listAreas(projectId.value), enabled: computed(() => dialog.value === "convert") });
async function act(action: () => Promise<unknown>) {
  if (busy.value) return;
  const originalProject = projectId.value;
  busy.value = true; error.value = "";
  try { await action(); dialog.value = null; }
  catch (e) { error.value = toAppError(e).message; }
  finally { busy.value = false; await refresh(originalProject); }
}
function resolve() { const options = decision.value?.options ?? []; choice.value = options.find(o => o.vote_count === leading.value)?.id ?? ""; dialog.value = "resolve"; }
async function removed() { await deleteDecision(id.value); await router.push({ name: "project.decisions", params: { projectId: projectId.value } }); }
const focusFallback = ref<HTMLElement | null>(null);
useExecutionDialogFocus(computed(() => dialog.value !== null), focusFallback);
</script>
<template>
  <section class="space-y-5 max-w-3xl fade-in">
    <RouterLink
      :to="{ name: 'project.decisions', params: { projectId } }"
      class="inline-flex min-h-11 items-center text-sm text-brand focus-ring"
    >
      All decisions
    </RouterLink>
    <div
      v-if="list.isPending.value"
      class="space-y-3"
      role="status"
      aria-label="Loading decision"
    >
      <SkeletonBlock height="40px" /><SkeletonBlock
        v-for="i in 2"
        :key="i"
        height="100px"
        rounded="0.75rem"
      />
    </div>
    <ErrorState
      v-else-if="list.error.value"
      :error="list.error.value"
      :retry="() => list.refetch()"
    />
    <p v-else-if="!decision">
      This decision is unavailable.
    </p>
    <template v-else>
      <h2
        ref="focusFallback"
        tabindex="-1"
        class="text-page-title focus-ring [overflow-wrap:anywhere]"
      >
        {{ decision.title }}
      </h2>
      <p
        v-if="decision.description"
        class="whitespace-pre-wrap break-words text-sm"
      >
        {{ decision.description }}
      </p>
      <p
        v-if="decision.status === 'resolved'"
        role="status"
        class="rounded-lg border border-success/20 bg-success-soft px-4 py-3 font-medium text-success [overflow-wrap:anywhere]"
      >
        Result: {{ selected?.title }} selected
      </p>
      <p
        v-else-if="decision.voting_deadline"
        class="text-sm"
      >
        {{ decision.deadline_reached ? 'Voting closed' : 'Voting closes' }} {{ useProjectTime(project?.timezone ?? 'UTC').dateTime(decision.voting_deadline) }} · {{ project?.timezone }}
      </p>
      <p
        v-else
        class="text-sm"
      >
        Open · No voting deadline
      </p>
      <p
        v-if="!decision.writable"
        class="text-sm"
      >
        This project is read-only.
      </p>
      <p class="text-meta text-muted">
        {{ decision.vote_count ? `${decision.vote_count} ${decision.vote_count === 1 ? 'vote' : 'votes'}` : 'No votes yet' }}. Votes are advisory; the creator or an Organizer confirms the final choice.
      </p>
      <p
        v-if="decision.can_vote"
        class="text-sm text-ink-soft"
      >
        {{ decision.my_option_id ? 'Your vote is recorded. You can choose a different option below.' : 'Choose an option to cast your vote.' }}
      </p>
      <div
        class="rounded-xl border border-line bg-surface divide-y divide-line"
        aria-live="polite"
      >
        <article
          v-for="option in decision.options"
          :key="option.id"
          class="p-4 flex flex-col sm:flex-row sm:items-center gap-3"
        >
          <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
            <h3 class="text-card-heading font-semibold">
              {{ option.title }}
            </h3>
            <p
              class="mt-1 text-sm"
              :class="option.id === decision.resolved_option_id ? 'text-success' : 'text-ink-soft'"
            >
              {{ option.vote_count }} {{ option.vote_count === 1 ? 'vote' : 'votes' }}<span v-if="leading > 0 && option.vote_count === leading"> · Leading{{ decision.options.filter(o => o.vote_count === leading).length > 1 ? ' (tied)' : '' }}</span><span v-if="option.id === decision.resolved_option_id"> · Selected</span>
            </p>
            <p
              v-if="option.estimated_cost_minor != null"
              class="mt-1 text-meta text-muted"
            >
              {{ money.format(option.estimated_cost_minor, project?.currency ?? 'GBP') }} estimated
            </p>
          </div>
          <AppButton
            v-if="decision.can_vote"
            :disabled="busy || option.id === decision.my_option_id"
            :aria-pressed="option.id === decision.my_option_id"
            variant="secondary"
            class="self-start sm:max-w-[45%]"
            @click="act(() => voteDecision(id, option.id))"
          >
            {{ option.id === decision.my_option_id ? '✓ Your vote' : `Vote for ${option.title}` }}
          </AppButton>
          <p
            v-else-if="option.id === decision.my_option_id"
            class="text-sm text-brand"
          >
            ✓ Your vote
          </p>
        </article>
      </div>
      <AppButton
        v-if="decision.can_vote && decision.my_option_id"
        :disabled="busy"
        variant="ghost"
        @click="act(() => voteDecision(id, null))"
      >
        Remove my vote
      </AppButton>
      <p
        v-if="error"
        role="alert"
        class="text-danger"
      >
        {{ error }}
      </p>
      <div
        v-if="decision.can_manage"
        class="border-t border-line pt-5 flex flex-wrap gap-2"
      >
        <AppButton
          variant="secondary"
          @click="dialog = 'share'"
        >
          Share decision
        </AppButton>
        <template v-if="decision.writable">
          <AppButton
            v-if="decision.status === 'open'"
            :disabled="busy"
            :variant="decision.can_vote ? 'secondary' : 'primary'"
            @click="resolve"
          >
            Resolve decision
          </AppButton>
          <AppButton
            v-if="decision.status === 'open'"
            variant="secondary"
            :disabled="busy"
            @click="dialog = 'edit'"
          >
            Edit decision
          </AppButton>
          <AppButton
            v-if="decision.status === 'resolved' && !decision.converted_activity_id"
            :disabled="busy"
            @click="dialog = 'convert'"
          >
            Create Activity
          </AppButton>
          <AppButton
            variant="ghost"
            :disabled="busy"
            class="text-danger"
            @click="dialog = 'delete'"
          >
            Delete decision
          </AppButton>
        </template>
      </div>
      <div
        v-if="decision.converted_activity_id"
        class="space-y-2"
      >
        <p>Activity created</p><AppButton :to="{ name: 'project.commitments', params: { projectId }, query: { commitment: decision.converted_activity_id } }">
          Open Activity
        </AppButton>
      </div>
      <ResourceComments
        :key="id"
        :resource="{ type: 'decision', id }"
        :timezone="project?.timezone ?? 'UTC'"
      />
      <DecisionFormDialog
        v-if="dialog === 'edit'"
        :decision="decision"
        :project-id="projectId"
        :currency="project?.currency ?? 'GBP'"
        :timezone="project?.timezone ?? 'UTC'"
        @close="dialog = null"
        @saved="dialog = null; refresh()"
      />
      <ShareLinkDialog
        v-if="dialog === 'share'"
        :resource="{ type: 'decision', id }"
        :read-only="!decision.writable"
        @close="dialog = null"
      />
      <AppModal
        v-if="dialog === 'resolve' || dialog === 'convert' || dialog === 'delete'"
        :open="true"
        :title="dialog === 'resolve' ? 'Resolve decision' : dialog === 'convert' ? 'Create Activity' : 'Delete decision'"
        :busy="busy"
        @close="dialog = null"
      >
        <div class="space-y-4">
          <template v-if="dialog === 'resolve'">
            <label class="block text-sm">Select final option<select
              v-model="choice"
              aria-label="Select final option"
              class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
            ><option
              v-for="option in decision.options"
              :key="option.id"
              :value="option.id"
            >{{ option.title }} — {{ option.vote_count }} votes</option></select></label>
            <p class="text-sm">
              This fixes the selected option and ends voting.
            </p>
            <AppButton
              :disabled="busy || !choice"
              @click="act(() => resolveDecision(id, choice))"
            >
              {{ busy ? 'Resolving…' : 'Confirm resolution' }}
            </AppButton>
          </template>
          <template v-else-if="dialog === 'convert'">
            <p class="font-medium break-words">
              {{ selected?.title }}
            </p><p>{{ money.format(selected?.estimated_cost_minor, project?.currency ?? 'GBP') }} estimated</p>
            <p class="text-meta text-muted">
              The selected title and estimate will become a normal Activity. You can edit it afterwards.
            </p>
            <p
              v-if="areas.isPending.value"
              role="status"
            >
              Loading Categories…
            </p><p
              v-if="areas.error.value"
              role="alert"
            >
              {{ areas.error.value.message }}
            </p>
            <label class="block text-sm">Category<select
              v-model="category"
              aria-label="Category"
              class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
            ><option
              disabled
              value=""
            >Choose Category</option><option
              v-for="area in areas.data.value"
              :key="area.id"
              :value="area.id"
            >{{ area.title }}</option></select></label>
            <p
              v-if="areas.data.value?.length === 0"
              class="text-sm"
            >
              Add a Category in Activities first.
            </p>
            <label class="block text-sm">Activity type<select
              v-model="activityType"
              aria-label="Activity type"
              class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-sm focus-ring"
            ><option
              v-for="type in ['other', 'task', 'booking', 'purchase', 'event']"
              :key="type"
              :value="type"
            >{{ type[0]?.toUpperCase() }}{{ type.slice(1) }}</option></select></label>
            <AppButton
              :disabled="busy || !category"
              @click="act(() => convertDecision(id, category, activityType))"
            >
              {{ busy ? 'Creating…' : 'Confirm Create Activity' }}
            </AppButton>
          </template>
          <template v-else>
            <p>Remove this decision from the project? Any converted Activity remains.</p><AppButton
              :disabled="busy"
              variant="danger"
              @click="act(removed)"
            >
              Confirm delete
            </AppButton>
          </template>
          <p
            v-if="error"
            role="alert"
            class="text-danger"
          >
            {{ error }}
          </p>
        </div>
      </AppModal>
    </template>
  </section>
</template>

<script setup lang="ts">
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
</script>
<template>
  <section class="py-6 space-y-5 max-w-3xl">
    <RouterLink
      :to="{ name: 'project.decisions', params: { projectId } }"
      class="text-14 underline focus-ring"
    >
      All decisions
    </RouterLink>
    <p
      v-if="list.isPending.value"
      role="status"
    >
      Loading decision…
    </p>
    <p
      v-else-if="list.error.value"
      role="alert"
    >
      {{ list.error.value.message }}
    </p>
    <p v-else-if="!decision">
      This decision is unavailable.
    </p>
    <template v-else>
      <h2 class="text-2xl font-semibold break-words">
        {{ decision.title }}
      </h2>
      <p
        v-if="decision.description"
        class="whitespace-pre-wrap break-words text-14"
      >
        {{ decision.description }}
      </p>
      <p
        v-if="decision.status === 'resolved'"
        role="status"
        class="font-medium"
      >
        {{ selected?.title }} selected
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
      <p
        v-if="!decision.writable"
        class="text-14"
      >
        This project is read-only.
      </p>
      <p class="text-13 text-muted">
        {{ decision.vote_count ? `${decision.vote_count} votes` : 'No votes yet' }}. Votes are advisory; the creator or an Organizer confirms the final choice.
      </p>
      <div
        class="space-y-3"
        aria-live="polite"
      >
        <article
          v-for="option in decision.options"
          :key="option.id"
          class="rounded-lg border p-4 space-y-2"
          :class="option.id === decision.resolved_option_id || option.id === decision.my_option_id ? 'border-ink' : 'border-line'"
        >
          <h3 class="font-medium break-words">
            {{ option.title }}
          </h3>
          <p
            v-if="option.estimated_cost_minor != null"
            class="text-14"
          >
            {{ money.format(option.estimated_cost_minor, project?.currency ?? 'GBP') }} estimated
          </p>
          <p class="text-14">
            {{ option.vote_count }} {{ option.vote_count === 1 ? 'vote' : 'votes' }}<span v-if="leading > 0 && option.vote_count === leading"> · Leading{{ decision.options.filter(o => o.vote_count === leading).length > 1 ? ' (tied)' : '' }}</span>
          </p>
          <p
            v-if="option.id === decision.resolved_option_id"
            class="font-medium"
          >
            Selected
          </p>
          <AppButton
            v-if="decision.can_vote"
            :disabled="busy || option.id === decision.my_option_id"
            :aria-pressed="option.id === decision.my_option_id"
            variant="secondary"
            @click="act(() => voteDecision(id, option.id))"
          >
            {{ option.id === decision.my_option_id ? '✓ Your vote' : `Vote for ${option.title}` }}
          </AppButton>
          <p
            v-else-if="option.id === decision.my_option_id"
            class="text-14"
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
        class="flex flex-wrap gap-2"
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
            <label class="block text-14">Select final option<select
              v-model="choice"
              aria-label="Select final option"
              class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-14 focus-ring"
            ><option
              v-for="option in decision.options"
              :key="option.id"
              :value="option.id"
            >{{ option.title }} — {{ option.vote_count }} votes</option></select></label>
            <p class="text-14">
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
            <p class="text-13 text-muted">
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
            <label class="block text-14">Category<select
              v-model="category"
              aria-label="Category"
              class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-14 focus-ring"
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
              class="text-14"
            >
              Add a Category in Activities first.
            </p>
            <label class="block text-14">Activity type<select
              v-model="activityType"
              aria-label="Activity type"
              class="mt-1 w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-14 focus-ring"
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

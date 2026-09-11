<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useCommitments } from "@/composables/useCommitments";
import { useMemberDirectory } from "@/composables/useProject";
import { useProjectContext } from "@/composables/useProjectContext";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { bookingStatusLabel, activityTypeLabel, commitmentStatusLabel } from "@/lib/activityWorkflows";
import { categoryLabel } from "@/lib/commitmentCategories";
import { recurrenceLabel } from "@/lib/recurrence";
import type { Commitment } from "@/services/commitments";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import AppButton from "@/components/ui/AppButton.vue";
import CommitmentFormDialog from "@/components/commitments/CommitmentFormDialog.vue";
import CommitmentDetailDialog from "@/components/commitments/CommitmentDetailDialog.vue";
import TasksPanel from "@/components/tasks/TasksPanel.vue";

const route = useRoute();
const router = useRouter();
const projectId = computed(() => String(route.params.projectId));
const { project, allowed, context } = useProjectContext();
const { commitments, isPending, isError, error, refetch } = useCommitments(projectId);
const { members } = useMemberDirectory(projectId);
const { format } = useMoney();

const currency = computed(() => project.value?.currency ?? "GBP");
const timezone = computed(() => project.value?.timezone ?? "UTC");
const archived = computed(() => project.value?.status === "archived");
const canEdit = computed(() => allowed("commitment.edit") && !archived.value);
const canEditTasks = computed(() => allowed("task.edit") && !archived.value);
const canEditPayments = computed(() => allowed("payment.edit") && !archived.value);

function canDelete(c: Commitment): boolean {
  if (!canEdit.value) return false;
  if (context.value?.role === "organizer") return true;
  const memberId = context.value?.memberId;
  return !!memberId && (c.created_by === memberId || c.owner_member_id === memberId);
}

const formOpen = ref(false);
const editingCommitment = ref<Commitment | null>(null);
const detailCommitmentId = ref<string | null>(null);
// Recomputed from the live list, so status/participant changes made inside the
// detail dialog are reflected immediately rather than showing a stale snapshot.
const detailCommitment = computed(() => commitments.value.find((c) => c.id === detailCommitmentId.value) ?? null);

watch(
  () => route.query.commitment,
  (id) => {
    detailCommitmentId.value = typeof id === "string" ? id : null;
  },
  { immediate: true },
);

watch([commitments, isPending, isError], () => {
  if (!isPending.value && !isError.value && detailCommitmentId.value && !detailCommitment.value) closeDetail();
});

function openCreate() {
  editingCommitment.value = null;
  formOpen.value = true;
}
function openEditFromDetail() {
  editingCommitment.value = detailCommitment.value;
  closeDetail();
  formOpen.value = true;
}
function closeForm() {
  formOpen.value = false;
  editingCommitment.value = null;
}

function openDetail(id: string) {
  void router.replace({ query: { ...route.query, commitment: id } });
}

function closeDetail() {
  const query = { ...route.query };
  delete query.commitment;
  delete query.occurrence;
  void router.replace({ query });
  detailCommitmentId.value = null;
}

const statusTone = (s: string) =>
  s === "cancelled" ? "neutral" : s === "completed" ? "accent" : "amber";

function ownerName(id: string | null): string | null {
  if (!id) return null;
  return members.value.find((m) => m.member_id === id)?.display_name ?? null;
}

const time = computed(() => useProjectTime(timezone.value));
</script>

<template>
  <div class="fade-in">
    <div class="flex items-center justify-between mb-4">
      <p class="text-14 text-ink-soft">
        {{ commitments.length }} {{ commitments.length === 1 ? "activity" : "activities" }}
      </p>
      <AppButton
        v-if="canEdit"
        size="sm"
        @click="openCreate"
      >
        New activity
      </AppButton>
    </div>

    <div
      v-if="isPending"
      class="space-y-2"
    >
      <SkeletonBlock
        v-for="i in 4"
        :key="i"
        height="64px"
        rounded="0.75rem"
      />
    </div>
    <ErrorState
      v-else-if="isError"
      :error="error"
      :retry="() => refetch()"
    />
    <EmptyState
      v-else-if="commitments.length === 0"
      message="No activities planned yet."
    >
      <template
        v-if="canEdit"
        #action
      >
        <AppButton
          size="sm"
          @click="openCreate"
        >
          Add the first activity
        </AppButton>
      </template>
    </EmptyState>
    <div
      v-else
      class="border rounded-xl divide-y border-line bg-surface"
    >
      <button
        v-for="c in commitments"
        :key="c.id"
        class="w-full text-left flex items-center gap-3.5 px-4 py-3.5 hover:bg-[#FBFBFA] focus-ring"
        @click="openDetail(c.id)"
      >
        <div class="min-w-0 flex-1">
          <div class="text-14 font-medium truncate">
            {{ c.title }}
          </div>
          <div class="text-13 text-muted capitalize">
            {{ activityTypeLabel(c.activity_type) }} · {{ categoryLabel(c.kind) }}
            <span v-if="c.starts_at"> · {{ time.dateOnly(c.starts_at) }}</span>
            <span v-if="c.recurrence_frequency"> · {{ recurrenceLabel(c.recurrence_frequency, c.recurrence_interval) }}</span>
            <span v-if="ownerName(c.owner_member_id)"> · {{ ownerName(c.owner_member_id) }}</span>
          </div>
        </div>
        <span
          v-if="c.estimated_cost_minor != null"
          class="text-13.5 text-ink-soft"
        >{{ format(c.estimated_cost_minor, currency) }}</span>
        <span class="flex flex-wrap gap-2">
          <StatusBadge
            :label="commitmentStatusLabel(c.activity_type, c.status)"
            :tone="statusTone(c.status)"
          />
          <StatusBadge
            v-if="c.activity_type === 'booking'"
            :label="'Booking: ' + bookingStatusLabel(c.status, c.booking_confirmed)"
            tone="neutral"
          />
        </span>
      </button>
    </div>

    <TasksPanel
      :project-id="projectId"
      :timezone="timezone"
      :can-edit="canEditTasks"
      :members="members"
      :commitments="commitments"
    />

    <CommitmentFormDialog
      :open="formOpen"
      :project-id="projectId"
      :currency="currency"
      :timezone="timezone"
      :project-profile="project?.profile ?? 'blank'"
      :member-options="members"
      :commitment="editingCommitment"
      @close="closeForm"
    />
    <CommitmentDetailDialog
      v-if="detailCommitment"
      :key="detailCommitment.id"
      :open="!!detailCommitment"
      :project-id="projectId"
      :currency="currency"
      :timezone="timezone"
      :commitment="detailCommitment"
      :occurrence-date="typeof route.query.occurrence === 'string' ? route.query.occurrence : undefined"
      :members="members"
      :can-edit="canEdit"
      :can-edit-payments="canEditPayments"
      :can-delete="canDelete(detailCommitment)"
      @close="closeDetail"
      @edit="openEditFromDetail"
    />
  </div>
</template>

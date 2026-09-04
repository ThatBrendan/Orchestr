<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { DateTime } from "luxon";
import { useFullTimeline } from "@/composables/useProject";
import { useCommitments } from "@/composables/useCommitments";
import { useMilestones, useDeleteMilestone } from "@/composables/useMilestones";
import { useProjectContext } from "@/composables/useProjectContext";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import type { Milestone } from "@/services/milestones";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import SectionHeading from "@/components/ui/SectionHeading.vue";
import UpcomingList from "@/components/timeline/UpcomingList.vue";
import MilestoneFormDialog from "@/components/milestones/MilestoneFormDialog.vue";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { project, allowed } = useProjectContext();
const timezone = computed(() => project.value?.timezone ?? "UTC");
const archived = computed(() => project.value?.status === "archived");
const canEdit = computed(() => allowed("milestone.edit") && !archived.value);

const timeline = useFullTimeline(projectId);
const { commitments } = useCommitments(projectId);
const { milestones, isPending: msPending, isError: msError, error: msErr, refetch: msRefetch } = useMilestones(projectId);
const del = useDeleteMilestone(projectId.value);
const toast = useToast();

const formOpen = ref(false);
const editingMilestone = ref<Milestone | null>(null);
function openCreate() {
  editingMilestone.value = null;
  formOpen.value = true;
}
function openEdit(m: Milestone) {
  editingMilestone.value = m;
  formOpen.value = true;
}

const confirmDeleteId = ref<string | null>(null);
async function doDelete() {
  if (!confirmDeleteId.value) return;
  try {
    await del.mutateAsync(confirmDeleteId.value);
    toast.success("Milestone deleted.");
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    confirmDeleteId.value = null;
  }
}

/** Derived only — no completion state (docs/BUSINESS_RULES.md MIL-4/MIL-5). */
function isPassed(m: Milestone): boolean {
  return DateTime.fromISO(m.on_date, { zone: timezone.value }) < DateTime.now().setZone(timezone.value).startOf("day");
}
</script>

<template>
  <div class="fade-in space-y-8">
    <div>
      <SectionHeading label="Full timeline" />
      <div v-if="timeline.isPending.value" class="mt-3 space-y-2">
        <SkeletonBlock v-for="i in 3" :key="i" height="72px" rounded="0.5rem" />
      </div>
      <ErrorState v-else-if="timeline.isError.value" class="mt-3" :error="timeline.error.value" :retry="() => timeline.refetch()" />
      <EmptyState v-else-if="timeline.events.value.length === 0" class="mt-3" message="Nothing on the timeline yet." />
      <UpcomingList v-else :events="timeline.events.value" :timezone="timezone" />
    </div>

    <div>
      <div class="flex items-center justify-between">
        <SectionHeading label="Milestones" />
        <AppButton v-if="canEdit" size="sm" @click="openCreate">New milestone</AppButton>
      </div>
      <div v-if="msPending" class="mt-3 space-y-2">
        <SkeletonBlock v-for="i in 2" :key="i" height="52px" rounded="0.5rem" />
      </div>
      <ErrorState v-else-if="msError" class="mt-3" :error="msErr" :retry="() => msRefetch()" />
      <EmptyState v-else-if="milestones.length === 0" class="mt-3" message="No milestones set.">
        <template v-if="canEdit" #action>
          <AppButton size="sm" @click="openCreate">Add a milestone</AppButton>
        </template>
      </EmptyState>
      <div v-else class="mt-3 border rounded-xl divide-y border-line bg-surface">
        <div v-for="m in milestones" :key="m.id" class="flex items-center gap-3.5 px-4 py-3.5">
          <div class="min-w-0 flex-1">
            <div class="text-14 font-medium">{{ m.title }}</div>
            <div class="text-13 text-muted">{{ DateTime.fromISO(m.on_date).toFormat("cccc d LLLL yyyy") }}</div>
          </div>
          <StatusBadge :label="isPassed(m) ? 'Passed' : 'Upcoming'" :tone="isPassed(m) ? 'neutral' : 'accent'" />
          <template v-if="canEdit">
            <AppButton variant="secondary" size="sm" @click="openEdit(m)">Edit</AppButton>
            <AppButton variant="ghost" size="sm" class="!text-danger" @click="confirmDeleteId = m.id">Delete</AppButton>
          </template>
        </div>
      </div>
    </div>

    <MilestoneFormDialog :open="formOpen" :project-id="projectId" :commitments="commitments" :milestone="editingMilestone" @close="formOpen = false" />
    <AppConfirmDialog
      :open="!!confirmDeleteId"
      title="Delete milestone"
      message="Delete this milestone? This can't be undone."
      confirm-label="Delete"
      danger
      :loading="del.isPending.value"
      @close="confirmDeleteId = null"
      @confirm="doDelete"
    />
  </div>
</template>

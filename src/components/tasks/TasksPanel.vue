<script setup lang="ts">
import { RouterLink } from "vue-router";
import { computed, reactive, ref } from "vue";
import { DateTime } from "luxon";
import { useQueryClient } from "@tanstack/vue-query";
import { useTasks, useCreateTask, useUpdateTask, useSetTaskStatus, useDeleteTask } from "@/composables/useTasks";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProjectTime } from "@/composables/useProjectTime";
import { useToast } from "@/composables/useToast";
import { useMoney } from "@/composables/useMoney";
import { canCompleteAssignedTask } from "@/lib/permissions";
import { toAppError } from "@/lib/errors";
import { invalidatePlanning } from "@/composables/invalidation";
import { qk } from "@/composables/keys";
import { REPEAT_OPTIONS, recurrenceLabel, repeatOption, type RepeatOptionValue } from "@/lib/recurrence";
import * as tasksService from "@/services/tasks";
import type { Task, TaskStatus } from "@/services/tasks";
import type { MemberDirectoryEntry } from "@/types/derived";
import type { Commitment } from "@/services/commitments";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import AppButton from "@/components/ui/AppButton.vue";
import { presentLabel } from "@/lib/presentation";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";

const props = defineProps<{
  onlyId?:string;
  financialId?:string|null;
  projectId: string;
  timezone: string;
  canEdit: boolean;
  members: MemberDirectoryEntry[];
  commitments: Commitment[];
}>();

const { tasks, isPending, isError, error, refetch } = useTasks(props.projectId);
const { context, project } = useProjectContext();
const time = useProjectTime(props.timezone);
const { format, toMinor } = useMoney();
const currency = computed(() => project.value?.currency ?? "GBP");
const linkedActivity = computed(() => props.commitments.find(c => c.id === addForm.commitment_id));
const activityCost = (c: Commitment | undefined) => c?.actual_cost_minor ?? c?.confirmed_cost_minor ?? c?.estimated_cost_minor ?? null;
function viewerCanComplete(t: Task) { return canCompleteAssignedTask(context.value?.role, context.value?.memberId, t.assignee_member_id, t.status, project.value?.status === "archived"); }
const toast = useToast();
const client = useQueryClient();

const create = useCreateTask(props.projectId);
const update = useUpdateTask(props.projectId);
const setStatus = useSetTaskStatus(props.projectId);
const del = useDeleteTask(props.projectId);

const assigneeCandidates = computed(() => props.members.filter((m) => m.status === "active"));

const NEXT: Record<TaskStatus, TaskStatus[]> = {
  open: ["in_progress", "done", "cancelled"],
  in_progress: ["open", "done", "cancelled"],
  done: ["open", "in_progress"],
  cancelled: ["open", "in_progress"],
};

const showAddForm = ref(false);
const addForm = reactive({
  title: "",
  item_type: "task",
  cost: "",
  assignee_member_id: "",
  due_on: "",
  commitment_id: "",
  repeat: "none" as RepeatOptionValue,
});
const addError = ref<string | null>(null);

async function submitAdd() {
  if (create.isPending.value || !props.canEdit) return;
  addError.value = null;
  if (!addForm.title.trim()) {
    addError.value = "Give the activity a title.";
    return;
  }
  const repeat = repeatOption(addForm.repeat);
  if (repeat.value !== "none" && !addForm.due_on) {
    addError.value = "Choose a due date before making this activity repeat.";
    return;
  }
  try {
    await create.mutateAsync({
      project_id: props.projectId,
      title: addForm.title.trim(),
      item_type: addForm.item_type,
      cost_minor: addForm.commitment_id ? activityCost(linkedActivity.value) : toMinor(addForm.cost, currency.value),
      assignee_member_id: addForm.assignee_member_id || null,
      due_on: addForm.due_on || null,
      commitment_id: addForm.commitment_id || null,
      recurrence_frequency: repeat.frequency,
      recurrence_interval: repeat.interval,
      recurrence_start_date: repeat.value === "none" ? null : addForm.due_on,
    });
    toast.success("Activity added.");
    addForm.title = "";
    addForm.item_type = "task";
    addForm.cost = "";
    addForm.assignee_member_id = "";
    addForm.due_on = "";
    addForm.commitment_id = "";
    addForm.repeat = "none";
    showAddForm.value = false;
  } catch (e) {
    addError.value = toAppError(e).message;
  }
}

function invalidateTaskDerived(taskId: string) {
  return invalidatePlanning(client, props.projectId, [qk.project.tasks(props.projectId), qk.task.occurrencesRoot(taskId)]);
}

async function completeNextTaskOccurrence(id: string) {
  const today = DateTime.now().setZone(props.timezone);
  const occurrences = await tasksService.listTaskOccurrences(
    id,
    today.minus({ days: 30 }).toISODate() ?? "",
    today.plus({ months: 6 }).toISODate() ?? "",
  );
  const next = occurrences.find((occurrence) => occurrence.status === "overdue" || occurrence.status === "upcoming");
  if (!next) {
    toast.info("No upcoming occurrence found.");
    return;
  }
  if (context.value?.role === "viewer") await tasksService.completeAssignedTask(id, next.occurrence_date);
  else await tasksService.completeTaskOccurrence(id, next.occurrence_date);
  await invalidateTaskDerived(id);
  return true;
}

async function skipNextTaskOccurrence(id: string) {
  const today = DateTime.now().setZone(props.timezone);
  const occurrences = await tasksService.listTaskOccurrences(
    id,
    today.minus({ days: 30 }).toISODate() ?? "",
    today.plus({ months: 6 }).toISODate() ?? "",
  );
  const next = occurrences.find((occurrence) => occurrence.status === "overdue" || occurrence.status === "upcoming");
  if (!next) {
    toast.info("No upcoming occurrence found.");
    return;
  }
  await tasksService.skipTaskOccurrence(id, next.occurrence_date);
  await invalidateTaskDerived(id);
  return true;
}

async function toggleDone(id: string, current: TaskStatus, recurring: boolean) {
  if (busy.value) return;
  occurrencePending.value = true;
  try {
    if (recurring && current !== "done") {
      if (await completeNextTaskOccurrence(id)) toast.success("Activity occurrence completed.");
      return;
    }
    if (context.value?.role === "viewer") {
      await tasksService.completeAssignedTask(id);
      await invalidateTaskDerived(id);
    } else await setStatus.mutateAsync({ id, status: current === "done" ? "open" : "done" });
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    occurrencePending.value = false;
  }
}

async function skipRecurringTask(id: string) {
  if (busy.value) return;
  occurrencePending.value = true;
  try {
    if (await skipNextTaskOccurrence(id)) toast.success("Activity occurrence skipped.");
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    occurrencePending.value = false;
  }
}

async function changeStatus(id: string, event: Event) {
  const control = event.target as HTMLSelectElement;
  const status = control.value as TaskStatus;
  try {
    await setStatus.mutateAsync({ id, status });
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    control.value = tasks.value.find((t) => t.id === id)?.status ?? "open";
  }
}

async function changeAssignee(id: string, event: Event) {
  const control = event.target as HTMLSelectElement;
  const assignee_member_id = control.value;
  try {
    await update.mutateAsync({ id, patch: { assignee_member_id: assignee_member_id || null } });
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    control.value = tasks.value.find((t) => t.id === id)?.assignee_member_id ?? "";
  }
}

const occurrencePending = ref(false);
const busy = computed(() => occurrencePending.value || setStatus.isPending.value || update.isPending.value || del.isPending.value);

const confirmDeleteId = ref<string | null>(null);
async function doDelete() {
  if (!confirmDeleteId.value || del.isPending.value) return;
  try {
    await del.mutateAsync(confirmDeleteId.value);
    toast.success("Activity deleted.");
    confirmDeleteId.value = null;
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

function memberName(id: string | null): string {
  if (!id) return "Unassigned";
  return props.members.find((m) => m.member_id === id)?.display_name ?? "Unknown";
}

function canDeleteTask(task: Task): boolean {
  if (context.value?.role === "organizer") return true;
  const memberId = context.value?.memberId;
  return !!memberId && (task.created_by === memberId || task.assignee_member_id === memberId);
}
</script>

<template>
  <div class="mt-9">
    <div class="flex items-center justify-between mb-3">
      <h2 class="font-display text-[17px] font-semibold">
        Activities
      </h2>
      <AppButton
        v-if="props.canEdit && !onlyId"
        variant="secondary"
        size="sm"
        @click="showAddForm = !showAddForm"
      >
        {{ showAddForm ? "Cancel" : "Add activity" }}
      </AppButton>
    </div>

    <form
      v-if="showAddForm"
      class="border rounded-xl p-3.5 mb-3 space-y-2.5 border-line bg-[#FBFBFA]"
      @submit.prevent="submitAdd"
    >
      <input
        v-model="addForm.title"
        aria-label="Activity title"
        placeholder="Activity title"
        class="w-full border rounded-lg px-3 py-2 text-14 focus-ring border-line"
      >
      <div class="grid sm:grid-cols-4 gap-2">
        <select
          v-model="addForm.item_type"
          aria-label="Activity type"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
        >
          <option value="task">
            Task
          </option>
          <option value="event">
            Event
          </option>
          <option value="booking">
            Booking
          </option>
          <option value="purchase">
            Purchase
          </option>
          <option value="other">
            Other
          </option>
        </select>
        <select
          v-model="addForm.assignee_member_id"
          aria-label="Assigned to"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
        >
          <option value="">
            Unassigned
          </option>
          <option
            v-for="m in assigneeCandidates"
            :key="m.member_id"
            :value="m.member_id"
          >
            {{ m.display_name }}
          </option>
        </select>
        <input
          v-model="addForm.due_on"
          aria-label="Activity due date"
          type="date"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line"
        >
        <select
          v-model="addForm.repeat"
          aria-label="Activity repeat"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
        >
          <option
            v-for="option in REPEAT_OPTIONS"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
        <select
          v-model="addForm.commitment_id"
          aria-label="Linked activity"
          class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface"
        >
          <option value="">
            No linked activity
          </option>
          <option
            v-for="c in props.commitments"
            :key="c.id"
            :value="c.id"
          >
            {{ c.title }}
          </option>
        </select>
      </div>
      <label
        v-if="!addForm.commitment_id"
        class="block text-13"
      >
        Cost ({{ currency }}, optional)
        <input
          v-model="addForm.cost"
          aria-label="Activity cost"
          type="text"
          inputmode="decimal"
          class="mt-1 w-full border rounded-lg px-3 py-2 focus-ring border-line"
        >
      </label>
      <p
        v-else
        class="text-13 text-muted"
      >
        Cost: {{ format(activityCost(linkedActivity), currency) }} — shared with the linked activity, counted once. Edit that activity to change its cost.
      </p>
      <p
        v-if="!addForm.commitment_id && addForm.cost"
        class="text-13 text-muted"
      >
        The linked activity will hold this cost and its payments.
      </p>
      <p
        v-if="addError"
        class="text-13 text-danger"
      >
        {{ addError }}
      </p>
      <AppButton
        size="sm"
        :loading="create.isPending.value"
        @click="submitAdd"
      >
        Add activity
      </AppButton>
    </form>

    <div
      v-if="isPending"
      class="space-y-2"
    >
      <SkeletonBlock
        v-for="i in 3"
        :key="i"
        height="48px"
        rounded="0.5rem"
      />
    </div>
    <ErrorState
      v-else-if="isError"
      :error="error"
      :retry="() => refetch()"
    />
    <EmptyState
      v-else-if="tasks.length === 0"
      message="No activities yet."
    />
    <div
      v-else
      class="border rounded-xl divide-y border-line bg-surface"
    >
      <div
        v-for="t in tasks.filter(row=>!onlyId||row.id===onlyId)"
        :key="t.id"
        class="flex flex-wrap items-start gap-3 px-4 py-3 sm:flex-nowrap sm:items-center"
      >
        <input
          type="checkbox"
          class="mt-1 shrink-0 rounded border-line sm:mt-0"
          :checked="t.status === 'done'"
          :disabled="(!props.canEdit && !viewerCanComplete(t)) || busy"
          :aria-label="`Complete ${t.title}`"
          @change="toggleDone(t.id, t.status, !!t.recurrence_frequency)"
        >
        <div class="min-w-0 flex-1 basis-[calc(100%-2rem)] sm:basis-auto">
          <div
            class="text-14 [overflow-wrap:anywhere]"
            :class="{ 'line-through text-muted': t.status === 'done' }"
          >
            {{ t.title }}
          </div>
          <div class="mt-1 flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1 text-13 text-muted">
            <span>{{ t.item_type === "task" ? "Task" : presentLabel(t.item_type) }}</span>
            <span class="min-w-0 max-w-full [overflow-wrap:anywhere]">{{ memberName(t.assignee_member_id) }}</span>
            <RouterLink
              v-if="t.commitment_id && (!onlyId || financialId)"
              :to="{ name: 'project.commitments', params: { projectId }, query: { commitment: t.commitment_id } }"
              class="text-brand-dark focus-ring"
            >
              Cost {{ format(activityCost(props.commitments.find(c => c.id === t.commitment_id)), currency) }} · Payments and details
            </RouterLink>
            <span v-if="t.due_on">Due {{ time.dateOnly(t.due_on) }}</span>
            <span v-if="t.recurrence_frequency">{{ recurrenceLabel(t.recurrence_frequency, t.recurrence_interval) }}</span>
          </div>
        </div>
        <div
          v-if="props.canEdit"
          class="basis-full pl-7 flex min-w-0 max-w-full flex-wrap items-center gap-2 sm:pl-0 sm:basis-auto"
        >
          <AppButton
            v-if="t.recurrence_frequency"
            variant="secondary"
            size="sm"
            :disabled="busy"
            @click="skipRecurringTask(t.id)"
          >
            Skip next
          </AppButton>
          <select
            class="min-w-0 max-w-full border rounded-lg px-2 py-1.5 text-13 focus-ring border-line bg-surface"
            :disabled="busy"
            :value="t.status"
            :aria-label="`Status of ${t.title}`"
            @change="changeStatus(t.id, $event)"
          >
            <option :value="t.status">
              {{ presentLabel(t.status) }}
            </option>
            <option
              v-for="s in NEXT[t.status]"
              :key="s"
              :value="s"
            >
              {{ presentLabel(s) }}
            </option>
          </select>
          <select
            class="min-w-0 max-w-full border rounded-lg px-2 py-1.5 text-13 focus-ring border-line bg-surface"
            :disabled="busy"
            :value="t.assignee_member_id ?? ''"
            :aria-label="`Assigned to for ${t.title}`"
            @change="changeAssignee(t.id, $event)"
          >
            <option value="">
              Unassigned
            </option>
            <option
              v-for="m in assigneeCandidates"
              :key="m.member_id"
              :value="m.member_id"
            >
              {{ m.display_name }}
            </option>
          </select>
          <AppButton
            v-if="canDeleteTask(t)"
            variant="ghost"
            size="sm"
            class="!text-danger"
            :disabled="busy"
            @click="confirmDeleteId = t.id"
          >
            Delete
          </AppButton>
        </div>
      </div>
    </div>

    <AppConfirmDialog
      :open="!!confirmDeleteId"
      title="Delete task"
      message="Delete this task? This can't be undone from here."
      confirm-label="Delete"
      danger
      :loading="del.isPending.value"
      @close="confirmDeleteId = null"
      @confirm="doDelete"
    />
  </div>
</template>

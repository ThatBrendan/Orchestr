<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import { DateTime } from "luxon";
import { useQueryClient } from "@tanstack/vue-query";
import { useTasks, useCreateTask, useUpdateTask, useSetTaskStatus, useDeleteTask } from "@/composables/useTasks";
import { useProjectContext } from "@/composables/useProjectContext";
import { useProjectTime } from "@/composables/useProjectTime";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
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
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";

const props = defineProps<{
  projectId: string;
  timezone: string;
  canEdit: boolean;
  members: MemberDirectoryEntry[];
  commitments: Commitment[];
}>();

const { tasks, isPending, isError, error, refetch } = useTasks(props.projectId);
const { context } = useProjectContext();
const time = useProjectTime(props.timezone);
const toast = useToast();
const client = useQueryClient();

const create = useCreateTask(props.projectId);
const update = useUpdateTask(props.projectId);
const setStatus = useSetTaskStatus(props.projectId);
const del = useDeleteTask(props.projectId);

const assigneeCandidates = computed(() => props.members.filter((m) => m.role !== "viewer" && m.status === "active"));

const NEXT: Record<TaskStatus, TaskStatus[]> = {
  open: ["in_progress", "done", "cancelled"],
  in_progress: ["open", "done", "cancelled"],
  done: ["open", "in_progress"],
  cancelled: ["open", "in_progress"],
};

const showAddForm = ref(false);
const addForm = reactive({
  title: "",
  assignee_member_id: "",
  due_on: "",
  commitment_id: "",
  repeat: "none" as RepeatOptionValue,
});
const addError = ref<string | null>(null);

async function submitAdd() {
  addError.value = null;
  if (!addForm.title.trim()) {
    addError.value = "Give the task a title.";
    return;
  }
  const repeat = repeatOption(addForm.repeat);
  if (repeat.value !== "none" && !addForm.due_on) {
    addError.value = "Choose a due date before making this task repeat.";
    return;
  }
  try {
    await create.mutateAsync({
      project_id: props.projectId,
      title: addForm.title.trim(),
      assignee_member_id: addForm.assignee_member_id || null,
      due_on: addForm.due_on || null,
      commitment_id: addForm.commitment_id || null,
      recurrence_frequency: repeat.frequency,
      recurrence_interval: repeat.interval,
      recurrence_start_date: repeat.value === "none" ? null : addForm.due_on,
    });
    toast.success("Task added.");
    addForm.title = "";
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
  void client.invalidateQueries({ queryKey: qk.project.tasks(props.projectId) });
  void client.invalidateQueries({ queryKey: qk.project.timeline(props.projectId) });
  void client.invalidateQueries({ queryKey: qk.project.upcoming(props.projectId) });
  void client.invalidateQueries({ queryKey: qk.project.health(props.projectId) });
  void client.invalidateQueries({ queryKey: qk.project.overview(props.projectId) });
  void client.invalidateQueries({ queryKey: qk.task.occurrencesRoot(taskId) });
  void client.invalidateQueries({ queryKey: qk.me.attention() });
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
  await tasksService.completeTaskOccurrence(id, next.occurrence_date);
  invalidateTaskDerived(id);
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
  invalidateTaskDerived(id);
}

async function toggleDone(id: string, current: TaskStatus, recurring: boolean) {
  try {
    if (recurring && current !== "done") {
      await completeNextTaskOccurrence(id);
      toast.success("Task occurrence completed.");
      return;
    }
    await setStatus.mutateAsync({ id, status: current === "done" ? "open" : "done" });
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

async function skipRecurringTask(id: string) {
  try {
    await skipNextTaskOccurrence(id);
    toast.success("Task occurrence skipped.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

async function changeStatus(id: string, status: TaskStatus) {
  try {
    await setStatus.mutateAsync({ id, status });
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

async function changeAssignee(id: string, assignee_member_id: string) {
  try {
    await update.mutateAsync({ id, patch: { assignee_member_id: assignee_member_id || null } });
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}

const confirmDeleteId = ref<string | null>(null);
async function doDelete() {
  if (!confirmDeleteId.value) return;
  try {
    await del.mutateAsync(confirmDeleteId.value);
    toast.success("Task deleted.");
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    confirmDeleteId.value = null;
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
      <h2 class="font-display text-[17px] font-semibold">Tasks</h2>
      <AppButton v-if="props.canEdit" variant="secondary" size="sm" @click="showAddForm = !showAddForm">
        {{ showAddForm ? "Cancel" : "Add task" }}
      </AppButton>
    </div>

    <form v-if="showAddForm" class="border rounded-xl p-3.5 mb-3 space-y-2.5 border-line bg-[#FBFBFA]" @submit.prevent="submitAdd">
      <input v-model="addForm.title" placeholder="Task title" class="w-full border rounded-lg px-3 py-2 text-14 focus-ring border-line" />
      <div class="grid sm:grid-cols-4 gap-2">
        <select v-model="addForm.assignee_member_id" class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface">
          <option value="">Unassigned</option>
          <option v-for="m in assigneeCandidates" :key="m.member_id" :value="m.member_id">{{ m.display_name }}</option>
        </select>
        <input v-model="addForm.due_on" type="date" class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line" />
        <select v-model="addForm.repeat" class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface">
          <option v-for="option in REPEAT_OPTIONS" :key="option.value" :value="option.value">{{ option.label }}</option>
        </select>
        <select v-model="addForm.commitment_id" class="border rounded-lg px-2.5 py-2 text-13.5 focus-ring border-line bg-surface">
          <option value="">No linked activity</option>
          <option v-for="c in props.commitments" :key="c.id" :value="c.id">{{ c.title }}</option>
        </select>
      </div>
      <p v-if="addError" class="text-13 text-danger">{{ addError }}</p>
      <AppButton size="sm" :loading="create.isPending.value" @click="submitAdd">Add task</AppButton>
    </form>

    <div v-if="isPending" class="space-y-2">
      <SkeletonBlock v-for="i in 3" :key="i" height="48px" rounded="0.5rem" />
    </div>
    <ErrorState v-else-if="isError" :error="error" :retry="() => refetch()" />
    <EmptyState v-else-if="tasks.length === 0" message="No tasks yet." />
    <div v-else class="border rounded-xl divide-y border-line bg-surface">
      <div v-for="t in tasks" :key="t.id" class="flex items-center gap-3 px-4 py-3">
        <input
          type="checkbox"
          class="rounded border-line"
          :checked="t.status === 'done'"
          :disabled="!props.canEdit"
          @change="toggleDone(t.id, t.status, !!t.recurrence_frequency)"
        />
        <div class="min-w-0 flex-1">
          <div class="text-14" :class="{ 'line-through text-muted': t.status === 'done' }">{{ t.title }}</div>
          <div class="text-13 text-muted">
            {{ memberName(t.assignee_member_id) }}
            <span v-if="t.due_on"> · Due {{ time.dateOnly(t.due_on) }}</span>
            <span v-if="t.recurrence_frequency"> · {{ recurrenceLabel(t.recurrence_frequency, t.recurrence_interval) }}</span>
          </div>
        </div>
        <template v-if="props.canEdit">
          <AppButton
            v-if="t.recurrence_frequency"
            variant="secondary"
            size="sm"
            @click="skipRecurringTask(t.id)"
          >
            Skip next
          </AppButton>
          <select
            class="border rounded-lg px-2 py-1.5 text-13 focus-ring border-line bg-surface"
            :value="t.status"
            @change="changeStatus(t.id, ($event.target as HTMLSelectElement).value as TaskStatus)"
          >
            <option :value="t.status">{{ t.status }}</option>
            <option v-for="s in NEXT[t.status]" :key="s" :value="s">{{ s }}</option>
          </select>
          <select
            class="border rounded-lg px-2 py-1.5 text-13 focus-ring border-line bg-surface"
            :value="t.assignee_member_id ?? ''"
            @change="changeAssignee(t.id, ($event.target as HTMLSelectElement).value)"
          >
            <option value="">Unassigned</option>
            <option v-for="m in assigneeCandidates" :key="m.member_id" :value="m.member_id">{{ m.display_name }}</option>
          </select>
          <AppButton
            v-if="canDeleteTask(t)"
            variant="ghost"
            size="sm"
            class="!text-danger"
            @click="confirmDeleteId = t.id"
          >
            Delete
          </AppButton>
        </template>
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

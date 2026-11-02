<script setup lang="ts">
import { computed } from "vue";
import type { HealthFinding } from "@/types/derived";
import { healthCodeTitle } from "@/lib/healthLabels";
import { normalizeHealthCopy, relativeDueText, userFacingActivityStatus } from "@/lib/presentation";
import { attentionDestination } from "@/lib/attentionDestination";
import { useDismissFinding, useSnoozeFinding, useReactivateFinding } from "@/composables/useHealth";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import type { IconName } from "@/components/ui/icons";

const props = defineProps<{
  finding: HealthFinding;
  projectId: string;
  canDismiss: boolean;
}>();

const emit = defineEmits<{ changed: [] }>();
const dismiss = useDismissFinding(props.projectId);
const snooze = useSnoozeFinding(props.projectId);
const reactivate = useReactivateFinding(props.projectId);
const toast = useToast();

const findingRef = computed(() => ({
  code: props.finding.code,
  subject_type: props.finding.subject_type,
  subject_id: props.finding.subject_id,
}));
const params = computed(() => (props.finding.params ?? {}) as Record<string, unknown>);
const dueText = computed(() => relativeDueText(params.value));
const displayMessage = computed(() => {
  if (["decision", "payment_schedule", "reimbursement"].includes(props.finding.subject_type)) return props.finding.message;
  const cleaned = normalizeHealthCopy(props.finding.message);
  const status = userFacingActivityStatus(String(params.value.status ?? ""));
  const pendingStatus = /pending|overdue/i.test(cleaned) || status === "Pending" || status === "Overdue";
  const base = props.finding.subject_label && !/This activity|This task|This .* is /i.test(cleaned)
    ? props.finding.subject_label
    : cleaned || "This activity is pending.";
  if (pendingStatus && !/This activity|This task|This .* is /i.test(base)) {
    return dueText.value ? `${base}${dueText.value}` : base;
  }
  if (dueText.value) return `${base}${base.endsWith(".") ? " " : " "}${dueText.value}`;
  return base;
});
const displayResolution = computed(() => {
  if (props.finding.subject_type === "reimbursement") return props.finding.resolution;
  const cleaned = normalizeHealthCopy(props.finding.resolution);
  if (/confirm it, complete it, or cancel it/i.test(cleaned)) return "Review activity";
  return /^\s*$/.test(cleaned) ? "" : cleaned;
});
const contextIcon = computed<IconName>(() => {
  if (props.finding.subject_type === "decision") return "flag";
  if (["payment_schedule", "reimbursement", "budget_category", "project"].includes(props.finding.subject_type)) return "coins";
  if (["commitment", "task"].includes(props.finding.subject_type)) return "checkCircle";
  return props.finding.severity === "ok" ? "checkCircle" : "alert";
});
const destination = computed(() => attentionDestination(props.projectId, props.finding));
const hasDirectDestination = computed(() => destination.value.label !== "Review in Health");

async function doDismiss() {
  try {
    await dismiss.mutateAsync(findingRef.value);
    toast.success("Dismissed.");
    emit("changed");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
async function doSnooze() {
  try {
    await snooze.mutateAsync({ finding: findingRef.value, days: 7 });
    toast.success("Snoozed for 7 days.");
    emit("changed");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
async function doReactivate() {
  try {
    await reactivate.mutateAsync(findingRef.value);
    toast.success("Restored.");
    emit("changed");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
</script>

<template>
  <article class="px-4 py-4 sm:px-5">
    <div class="flex flex-col gap-3 sm:flex-row sm:items-start">
      <div
        v-if="finding.severity !== 'ok'"
        class="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-lg"
        :class="finding.severity === 'blocker' ? 'bg-danger-soft text-danger' : finding.severity === 'warning' ? 'bg-warning-soft text-warning' : 'bg-brand-soft text-brand'"
        aria-hidden="true"
      >
        <AppIcon
          :name="contextIcon"
          :size="20"
        />
      </div>
      <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
        <p
          class="text-meta"
          :class="finding.severity === 'blocker' ? 'text-danger' : finding.severity === 'warning' ? 'text-warning' : finding.severity === 'ok' ? 'text-success' : 'text-muted'"
        >
          {{ {blocker:'Blocker',warning:'Warning',info:'Information',ok:'Passed'}[finding.severity] }}<span v-if="finding.dismissed"> · {{ finding.snoozed_until ? 'Snoozed until ' + finding.snoozed_until : 'Dismissed' }}</span>
        </p>
        <h4 class="mt-1 text-card-heading font-semibold">
          {{ healthCodeTitle(finding.code) }}
        </h4>
        <p
          v-if="finding.subject_label"
          class="mt-1 text-sm font-medium text-ink"
        >
          {{ finding.subject_label }}
        </p>
        <p
          v-if="displayMessage !== finding.subject_label"
          class="mt-1 text-sm text-ink-soft"
        >
          {{ displayMessage }}
        </p>
        <p
          v-if="displayResolution && finding.severity !== 'ok'"
          class="mt-1 text-meta text-muted"
        >
          {{ displayResolution }}
        </p>
      </div>
      <RouterLink
        v-if="hasDirectDestination && finding.severity !== 'ok'"
        :to="destination.to"
        class="min-h-11 inline-flex shrink-0 items-center justify-center rounded-lg px-3 text-sm font-medium text-brand hover:bg-brand-soft focus-ring sm:self-start"
      >
        {{ destination.label }}
        <AppIcon
          name="chevronRight"
          :size="16"
          class="ml-1"
        />
      </RouterLink>
    </div>

    <div
      v-if="props.canDismiss && (finding.severity !== 'ok' || finding.dismissible || finding.dismissed)"
      class="mt-3 flex flex-wrap gap-2 sm:ml-[3.25rem]"
    >
      <template v-if="!props.finding.dismissible">
        <span class="text-meta text-muted italic">Can only be resolved by fixing the underlying issue.</span>
      </template>
      <template v-else-if="props.finding.dismissed">
        <AppButton
          variant="secondary"
          size="sm"
          :loading="reactivate.isPending.value"
          @click="doReactivate"
        >
          Restore
        </AppButton>
      </template>
      <template v-else>
        <AppButton
          variant="ghost"
          size="sm"
          :loading="dismiss.isPending.value"
          :aria-label="`Dismiss: ${healthCodeTitle(finding.code)}`"
          @click="doDismiss"
        >
          Dismiss
        </AppButton>
        <AppButton
          variant="ghost"
          size="sm"
          :loading="snooze.isPending.value"
          :aria-label="`Snooze 7 days: ${healthCodeTitle(finding.code)}`"
          @click="doSnooze"
        >
          Snooze 7 days
        </AppButton>
      </template>
    </div>
  </article>
</template>

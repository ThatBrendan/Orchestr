<script setup lang="ts">
import { computed } from "vue";
import type { HealthFinding } from "@/types/derived";
import { healthCodeTitle } from "@/lib/healthLabels";
import { normalizeHealthCopy, relativeDueText, userFacingActivityStatus } from "@/lib/presentation";
import { useDismissFinding, useSnoozeFinding, useReactivateFinding } from "@/composables/useHealth";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";


import AppButton from "@/components/ui/AppButton.vue";

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
    ? `${props.finding.subject_label}`
    : cleaned || "This activity is pending.";
  if (pendingStatus && !/This activity|This task|This .* is /i.test(base)) {
    const formatted = /^\s*\w/.test(base) ? base : "This activity is pending.";
    return dueText.value ? `${formatted}${formatted.endsWith(".") ? " " : " "}${dueText.value}` : formatted;
  }
  if (dueText.value) return `${base}${base.endsWith(".") ? " " : " "}${dueText.value}`;
  return base;
});
const displayResolution = computed(() => {
  if (props.finding.subject_type === "reimbursement") return props.finding.resolution;
  const cleaned = normalizeHealthCopy(props.finding.resolution);
  if (/confirm it, complete it, or cancel it/i.test(cleaned)) return "Review activity";
  if (/^\s*$/u.test(cleaned)) return "";
  return cleaned;
});

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
  <article class="px-4 py-4">
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
        class="mt-1 text-sm text-ink-soft"
      >
        {{ finding.subject_label }}
      </p>
      <p
        v-if="displayMessage !== finding.subject_label"
        class="text-sm text-ink-soft mt-2"
      >
        {{ displayMessage }}
      </p>
      <RouterLink
        v-if="finding.subject_type === 'decision'"
        :to="{ name: 'project.decision', params: { projectId, decisionId: finding.subject_id } }"
        class="min-h-11 inline-flex items-center rounded-lg text-sm text-brand underline focus-ring"
      >
        Open decision
      </RouterLink>
      <RouterLink
        v-else-if="['payment_schedule', 'reimbursement'].includes(finding.subject_type)"
        :to="{name: 'project.commitments', params: {projectId}, query: {commitment: String(params.activity_id), section: finding.subject_type === 'reimbursement' ? 'reimbursements' : 'payments'}}"
        class="min-h-11 inline-flex items-center rounded-lg text-sm text-brand underline focus-ring"
      >
        Open payments
      </RouterLink>
      <RouterLink
        v-else-if="['commitment','task'].includes(finding.subject_type) && finding.subject_id"
        :to="{name:'project.commitments',params:{projectId},query:{[finding.subject_type==='task'?'item':'commitment']:finding.subject_id}}"
        class="min-h-11 inline-flex items-center rounded-lg text-sm text-brand underline focus-ring"
      >
        Review activity
      </RouterLink>
      <p
        v-if="displayResolution"
        class="text-meta text-muted mt-1"
      >
        {{ displayResolution }}
      </p>

      <div
        v-if="props.canDismiss && (finding.severity !== 'ok' || finding.dismissible || finding.dismissed)"
        class="mt-2 flex flex-wrap gap-2"
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
    </div>
  </article>
</template>

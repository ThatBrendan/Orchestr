<script setup lang="ts">
import { computed } from "vue";
import type { HealthFinding } from "@/types/derived";
import { healthCodeTitle } from "@/lib/healthLabels";
import { useDismissFinding, useSnoozeFinding, useReactivateFinding } from "@/composables/useHealth";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import SeverityIcon from "@/components/ui/SeverityIcon.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import AppButton from "@/components/ui/AppButton.vue";

const props = defineProps<{
  finding: HealthFinding;
  projectId: string;
  canDismiss: boolean;
}>();

const dismiss = useDismissFinding(props.projectId);
const snooze = useSnoozeFinding(props.projectId);
const reactivate = useReactivateFinding(props.projectId);
const toast = useToast();

const findingRef = computed(() => ({
  code: props.finding.code,
  subject_type: props.finding.subject_type,
  subject_id: props.finding.subject_id,
}));

async function doDismiss() {
  try {
    await dismiss.mutateAsync(findingRef.value);
    toast.success("Dismissed.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
async function doSnooze() {
  try {
    await snooze.mutateAsync({ finding: findingRef.value, days: 7 });
    toast.success("Snoozed for 7 days.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
async function doReactivate() {
  try {
    await reactivate.mutateAsync(findingRef.value);
    toast.success("Restored.");
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
</script>

<template>
  <div class="flex items-start gap-3 px-4 py-3.5">
    <SeverityIcon :severity="props.finding.severity" />
    <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-14 font-medium">{{ healthCodeTitle(props.finding.code) }}</span>
        <StatusBadge
          v-if="props.finding.subject_label"
          :label="props.finding.subject_label"
          tone="neutral"
        />
        <StatusBadge
          v-if="props.finding.dismissed && props.finding.snoozed_until"
          :label="`Snoozed until ${props.finding.snoozed_until}`"
          tone="amber"
        />
        <StatusBadge
          v-else-if="props.finding.dismissed"
          label="Dismissed"
          tone="neutral"
        />
      </div>
      <p class="text-13.5 text-ink-soft mt-0.5">
        {{ props.finding.message }}
      </p>
      <p class="text-13 text-muted mt-1">
        {{ props.finding.resolution }}
      </p>

      <div
        v-if="props.canDismiss"
        class="mt-2 flex gap-2"
      >
        <template v-if="!props.finding.dismissible">
          <span class="text-13 text-muted italic">Can only be resolved by fixing the underlying issue.</span>
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
            variant="secondary"
            size="sm"
            :loading="dismiss.isPending.value"
            @click="doDismiss"
          >
            Dismiss
          </AppButton>
          <AppButton
            variant="ghost"
            size="sm"
            :loading="snooze.isPending.value"
            @click="doSnooze"
          >
            Snooze 7 days
          </AppButton>
        </template>
      </div>
    </div>
  </div>
</template>

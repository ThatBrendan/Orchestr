<script setup lang="ts">
import { computed } from "vue";
import AppIcon from "./AppIcon.vue";
import type { FindingSeverity } from "@/types";

const props = defineProps<{ severity: FindingSeverity }>();

const style = computed(
  () =>
    ({
      blocker: { box: "bg-danger-soft text-danger", icon: "alert" as const },
      warning: { box: "bg-amber-soft text-amber", icon: "alert" as const },
      info: { box: "bg-[#EFEFEC] text-ink-soft", icon: "alert" as const },
      ok: { box: "bg-success-soft text-success", icon: "checkCircle" as const },
    })[props.severity],
);
</script>

<template>
  <div
    class="w-8 h-8 rounded-md flex items-center justify-center shrink-0"
    :class="style.box"
  >
    <AppIcon
      :name="style.icon"
      :size="16"
    />
  </div>
</template>

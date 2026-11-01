<script setup lang="ts">
import { computed } from "vue";
import type { Item } from "@/services/items";
import type { MemberDirectoryEntry } from "@/types/derived";
import { itemStatusLabel, itemTypeLabel } from "@/lib/itemPresentation";
import { useMoney } from "@/composables/useMoney";
import AppAvatar from "@/components/ui/AppAvatar.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
const props = defineProps<{ item: Item; members: MemberDirectoryEntry[]; timezone: string; currency: string }>();
defineEmits<{ open: [] }>();
const owner = computed(() => props.members.find(member => member.member_id === props.item.assignee_member_id));
const { format } = useMoney();
const dateParts = computed(() => {
 if (!props.item.item_date) return null;
 const value = new Date(props.item.item_date);
 if (Number.isNaN(value.getTime())) return null;
 return {
  month: value.toLocaleDateString(undefined, { timeZone: props.timezone, month: 'short' }).toUpperCase(),
  day: value.toLocaleDateString(undefined, { timeZone: props.timezone, day: 'numeric' }),
 };
});
const statusLabel = computed(() => itemStatusLabel(props.item));
const statusComplete = computed(() => ['completed', 'done'].includes(props.item.status));
const statusCancelled = computed(() => props.item.status === 'cancelled');
</script>
<template>
  <button
    type="button"
    class="w-full min-w-0 min-h-20 border-t border-line text-left px-3 sm:px-4 py-3.5 flex items-start gap-3 sm:gap-4 hover:bg-surface-subtle focus-ring transition-colors"
    :aria-label="`Open activity: ${item.title}`"
    @click="$emit('open')"
  >
    <span
      v-if="dateParts"
      class="flex h-[58px] w-[58px] shrink-0 flex-col items-center justify-center rounded-xl border border-brand-soft bg-brand-soft text-brand"
      aria-hidden="true"
    >
      <span class="text-[10px] font-bold tracking-wide">{{ dateParts.month }}</span>
      <span class="mt-0.5 text-xl font-semibold leading-none">{{ dateParts.day }}</span>
    </span>
    <span
      v-else
      class="flex h-[58px] w-[58px] shrink-0 flex-col items-center justify-center rounded-xl border border-line bg-surface-subtle text-muted"
    >
      <AppIcon
        name="calendar"
        :size="20"
        aria-hidden="true"
      />
      <span class="mt-1 text-[9px] font-semibold uppercase">No date</span>
    </span>
    <span class="min-w-0 flex-1 [overflow-wrap:anywhere]">
      <span class="block text-card-heading font-semibold text-ink">{{ item.title }}</span>
      <span
        v-if="item.notes"
        class="mt-1 block max-w-xl truncate text-sm text-ink-soft"
      >
        {{ item.notes }}
      </span>
      <span class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-ink-soft">
        <span class="inline-flex min-w-0 items-center gap-2">
          <AppAvatar
            v-if="owner"
            :name="owner.display_name"
            :url="owner.avatar_url"
            :size="24"
          />
          {{ owner?.display_name ?? 'Unassigned' }}
        </span>
        <span
          class="inline-flex min-h-6 items-center rounded-full px-2.5 text-xs font-semibold"
          :class="statusComplete ? 'bg-success-soft text-success' : statusCancelled ? 'bg-surface-subtle text-muted' : 'bg-brand-soft text-brand'"
        >
          {{ statusLabel }}
        </span>
      </span>
      <span class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-meta text-muted">
        <span>{{ itemTypeLabel(item.item_type) }}</span>
        <span
          v-if="item.cost_minor != null"
          class="tnum"
        >{{ format(item.cost_minor, currency) }}</span>
      </span>
    </span>
    <AppIcon
      name="chevronRight"
      :size="18"
      class="shrink-0 mt-1 text-brand"
    />
  </button>
</template>

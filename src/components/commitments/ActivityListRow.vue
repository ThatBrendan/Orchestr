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
</script>
<template>
  <button
    type="button"
    class="w-full min-w-0 text-left px-4 py-3.5 flex items-start gap-3 hover:bg-surface-subtle focus-ring transition-colors"
    :aria-label="`Open activity: ${item.title}`"
    @click="$emit('open')"
  >
    <span class="min-w-0 flex-1 [overflow-wrap:anywhere]">
      <span class="block text-card-heading font-semibold text-ink">{{ item.title }}</span>
      <span class="mt-2 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-ink-soft">
        <span>{{ item.item_date ? new Date(item.item_date).toLocaleDateString(undefined, { timeZone: timezone, day: 'numeric', month: 'short', year: 'numeric' }) : 'No date set' }}</span>
        <span class="inline-flex min-w-0 items-center gap-2">
          <AppAvatar
            v-if="owner"
            :name="owner.display_name"
            :url="owner.avatar_url"
            :size="24"
          />
          {{ owner?.display_name ?? 'Unassigned' }}
        </span>
      </span>
      <span class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-meta text-muted">
        <span :class="['completed', 'done'].includes(item.status) ? 'text-success' : item.status === 'overdue' ? 'text-warning' : ''">{{ itemStatusLabel(item) }}</span>
        <span>{{ itemTypeLabel(item.item_type) }}</span>
        <span
          v-if="item.cost_minor != null"
          class="tnum"
        >Cost {{ format(item.cost_minor, currency) }}</span>
      </span>
    </span>
    <AppIcon
      name="chevronRight"
      :size="18"
      class="shrink-0 mt-1 text-brand"
    />
  </button>
</template>

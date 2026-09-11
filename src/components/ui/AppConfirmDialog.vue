<script setup lang="ts">
import AppModal from "./AppModal.vue";
import AppButton from "./AppButton.vue";

const props = withDefaults(
  defineProps<{
    open: boolean;
    title: string;
    message: string;
    confirmLabel?: string;
    danger?: boolean;
    loading?: boolean;
  }>(),
  { confirmLabel: "Confirm", danger: false, loading: false },
);
const emit = defineEmits<{ close: []; confirm: [] }>();
</script>

<template>
  <AppModal
    :open="props.open"
    :busy="props.loading"
    :title="props.title"
    @close="emit('close')"
  >
    <p class="text-14 text-ink-soft">
      {{ props.message }}
    </p>
    <template #footer>
      <AppButton
        variant="secondary"
        size="sm"
        :disabled="props.loading"
        @click="emit('close')"
      >
        Cancel
      </AppButton>
      <AppButton
        size="sm"
        :loading="props.loading"
        :class="props.danger ? '!bg-danger hover:!bg-danger' : ''"
        @click="emit('confirm')"
      >
        {{ props.confirmLabel }}
      </AppButton>
    </template>
  </AppModal>
</template>

<script setup lang="ts">
import { onScopeDispose, ref, watch } from "vue";
import { createShareLink, getShareLink, regenerateShareLink, disableShareLink, type ShareableResource } from "@/services/shareLinks";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import { toAppError } from "@/lib/errors";
const props = defineProps<{ resource: ShareableResource; readOnly: boolean }>();
const emit = defineEmits<{ close: [] }>();
const link = ref<string | null>(null), loading = ref(false), busy = ref(false), error = ref(""), feedback = ref("");
const confirm = ref(false);
let generation = 0;
onScopeDispose(() => { generation++; });
async function load() {
  const current = ++generation; link.value = null; loading.value = true; error.value = "";
  try { const result = await getShareLink(props.resource); if (current === generation) link.value = result.url; }
  catch (e) { if (current === generation) error.value = toAppError(e).message; }
  finally { if (current === generation) loading.value = false; }
}
watch(() => [props.resource.type, props.resource.id], load, { immediate: true });
async function change(action: "create" | "regenerate" | "disable") {
  if (busy.value || props.readOnly) return;
  const current = generation; busy.value = true; error.value = ""; feedback.value = "";
  try {
    let result: string | null = null;
    if (action === "disable") await disableShareLink(props.resource);
    else result = await (action === "create" ? createShareLink : regenerateShareLink)(props.resource);
    if (current !== generation) return;
    link.value = result; confirm.value = false;
    feedback.value = action === "disable" ? "Link disabled." : "Link ready to copy.";
  } catch (e) { if (current === generation) error.value = toAppError(e).message; }
  finally { if (current === generation) busy.value = false; }
}
async function copy() {
  if (!link.value) return;
  try { await navigator.clipboard.writeText(link.value); feedback.value = "Link copied"; }
  catch { feedback.value = "Copy the link from the field below."; }
}
</script>
<template>
  <AppModal
    :open="true"
    :title="resource.type === 'decision' ? 'Share decision' : 'Share activity'"
    :busy="busy"
    @close="emit('close')"
  >
    <div class="space-y-4">
      <p class="text-14">
        Only people who already have access to this project can open this link.
      </p>
      <p
        v-if="loading"
        role="status"
        class="text-14"
      >
        Loading link…
      </p>
      <p
        v-if="error"
        role="alert"
        class="text-14 text-danger"
      >
        {{ error }}
      </p>
      <AppButton
        v-if="error"
        variant="secondary"
        :disabled="loading || busy"
        @click="load"
      >
        Retry
      </AppButton>
      <template v-if="!loading && !error">
        <div class="flex flex-wrap gap-2">
          <AppButton
            v-if="link"
            :disabled="busy"
            @click="copy"
          >
            Copy link
          </AppButton>
          <AppButton
            v-else
            :disabled="readOnly || busy"
            :loading="busy"
            @click="change('create')"
          >
            Create link
          </AppButton>
          <AppButton
            v-if="link"
            variant="secondary"
            :disabled="readOnly || busy"
            @click="confirm = true"
          >
            Regenerate link
          </AppButton>
          <AppButton
            v-if="link"
            variant="secondary"
            :disabled="readOnly || busy"
            :loading="busy"
            @click="change('disable')"
          >
            Disable link
          </AppButton>
        </div>
        <label
          v-if="link"
          class="block text-13"
        >Share link
          <input
            :value="link"
            readonly
            class="mt-1 block w-full min-w-0 rounded-lg border border-line p-2 text-13 focus-ring"
            @focus="($event.target as HTMLInputElement).select()"
          >
        </label>
        <p
          v-if="readOnly"
          class="text-13 text-muted"
        >
          This project is archived and read-only.
        </p>
      </template>
      <p
        v-if="feedback"
        role="status"
        class="text-14"
      >
        {{ feedback }}
      </p>
    </div>
    <AppConfirmDialog
      :open="confirm"
      title="Regenerate link?"
      message="The current link will stop working. The activity and project access will stay unchanged."
      confirm-label="Regenerate"
      :loading="busy"
      @close="confirm = false"
      @confirm="change('regenerate')"
    />
  </AppModal>
</template>

<script setup lang="ts">
import { ref, watch } from "vue";
import { useQueryClient } from "@tanstack/vue-query";
import * as joins from "@/services/joinLinks";
import { toAppError } from "@/lib/errors";
import { qk } from "@/composables/keys";
import AppAvatar from "@/components/ui/AppAvatar.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import AppButton from "@/components/ui/AppButton.vue";
const props = defineProps<{ projectId: string; readOnly: boolean }>();
const emit = defineEmits<{
  busyChange: [busy: boolean];
  accessChange: [value: { loading: boolean; pendingCount: number; error: string }];
}>();
const client = useQueryClient();
const access = ref<joins.JoinAccess>();
const loading = ref(false), busy = ref(false), reviewing = ref<string | null>(null);
const link = ref(""), feedback = ref(""), error = ref("");
const offset = ref(0);
let generation = 0;
async function load() {
  const current = ++generation;
  loading.value = true; error.value = "";
  emit("accessChange", { loading: true, pendingCount: access.value?.pending_count ?? 0, error: error.value });
  try { const result = await joins.getJoinAccess(props.projectId, offset.value); if (current === generation) { access.value = result; } }
  catch (e) { if (current === generation) error.value = toAppError(e).message; }
  finally { if (current === generation) { loading.value = false; emit("accessChange", { loading: false, pendingCount: access.value?.pending_count ?? 0, error: error.value }); } }
}
watch(() => props.projectId, () => { link.value = ""; access.value = undefined; offset.value = 0; void load(); }, { immediate: true });
async function disable() {
  if (busy.value) return;
  busy.value = true; error.value = "";
  emit("busyChange", true);
  try { await joins.disableJoinLink(props.projectId); link.value = ""; await load(); feedback.value = "Join link disabled."; }
  catch (e) { error.value = toAppError(e).message; }
  finally { busy.value = false; emit("busyChange", false); }
}
async function copy() {
  if (busy.value || props.readOnly) return;
  busy.value = true; error.value = ""; feedback.value = "";
  emit("busyChange", true);
  try {
    link.value = await joins.ensureJoinLink(props.projectId);
    try { await navigator.clipboard.writeText(link.value); link.value = ""; feedback.value = "Invite link copied."; }
    catch { feedback.value = "Copy the invite link from the field below."; }
    await load();
  } catch (e) { error.value = toAppError(e).message; }
  finally { busy.value = false; emit("busyChange", false); }
}
async function review(id: string, approve: boolean) {
  if (reviewing.value) return;
  reviewing.value = id; error.value = "";
  try {
    await joins.reviewJoinRequest(id, approve);
    offset.value = 0; await load();
    await Promise.all([qk.project.root(props.projectId), qk.me.notifications(), qk.me.people()].map(queryKey => client.invalidateQueries({ queryKey })));
    feedback.value = approve ? "Access approved." : "Access request declined.";
  } catch (e) { error.value = toAppError(e).message; }
  finally { reviewing.value = null; }
}
async function page(delta: number) { offset.value = Math.max(0, offset.value + delta); await load(); }

defineExpose({ copy });
</script>
<template>
  <div class="space-y-3 min-w-0">
    <p
      v-if="feedback"
      role="status"
      class="text-meta text-success"
    >
      {{ feedback }}
    </p>
    <div
      v-if="loading"
      role="status"
      aria-label="Loading access requests"
      class="space-y-3"
    >
      <div
        v-for="i in 2"
        :key="i"
        class="flex gap-3 rounded-xl border border-line p-4"
      >
        <SkeletonBlock
          width="44px"
          height="44px"
          rounded="50%"
        />
        <div class="flex-1 space-y-2">
          <SkeletonBlock
            width="55%"
            height="20px"
          /><SkeletonBlock
            width="35%"
            height="16px"
          />
        </div>
      </div>
    </div>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-danger"
    >
      {{ error }}
    </p>
    <AppButton
      v-if="error"
      variant="secondary"
      :disabled="loading"
      @click="load"
    >
      Retry
    </AppButton>
    <template v-if="access">
      <section
        v-if="access.pending_count"
        aria-labelledby="join-requests-heading"
        class="space-y-3"
      >
        <h4
          id="join-requests-heading"
          class="text-card-heading font-semibold"
        >
          Join requests
        </h4>
        <article
          v-for="item in access.requests"
          :key="item.id"
          class="rounded-xl border border-warning/20 bg-surface p-3 flex flex-wrap items-center justify-between gap-3 [overflow-wrap:anywhere]"
        >
          <div class="flex min-w-0 flex-1 basis-full sm:basis-0 items-start gap-3">
            <span aria-hidden="true"><AppAvatar
              :name="item.display_name"
              :size="44"
            /></span>
            <div class="min-w-0">
              <h5 class="text-card-heading font-semibold">
                {{ item.display_name }}
              </h5>
              <p class="mt-1 text-meta text-warning">
                Awaiting approval
              </p>
              <time
                :datetime="item.requested_at"
                class="mt-1 block text-meta text-muted"
              >
                Requested {{ new Date(item.requested_at).toLocaleString() }}
              </time>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <AppButton
              variant="secondary"
              size="sm"
              :aria-label="`Decline ${item.display_name}`"
              :disabled="!!reviewing || readOnly"
              :aria-busy="reviewing === item.id"
              @click="review(item.id, false)"
            >
              Decline
            </AppButton>
            <AppButton
              size="sm"
              :aria-label="`Approve ${item.display_name}`"
              :disabled="!!reviewing || readOnly"
              :loading="reviewing === item.id"
              :aria-busy="reviewing === item.id"
              @click="review(item.id, true)"
            >
              Approve
            </AppButton>
          </div>
        </article>
      </section>
      <div
        v-if="access.pending_count > 25 || offset"
        class="flex gap-2"
      >
        <AppButton
          variant="secondary"
          :disabled="!offset || loading"
          @click="page(-25)"
        >
          Previous
        </AppButton>
        <AppButton
          variant="secondary"
          :disabled="offset + 25 >= access.pending_count || loading"
          @click="page(25)"
        >
          Next
        </AppButton>
      </div>
      <div class="space-y-3">
        <details
          v-if="access.active"
          class="text-sm"
        >
          <summary class="min-h-11 py-3 cursor-pointer rounded-lg focus-ring text-muted">
            Invite link settings
          </summary>
          <AppButton
            variant="secondary"
            :loading="busy"
            :aria-busy="busy"
            :disabled="readOnly"
            @click="disable"
          >
            Disable link
          </AppButton>
        </details>
        <label
          v-if="link"
          class="block text-meta"
        >Join link
          <input
            :value="link"
            readonly
            class="mt-1 block w-full min-w-0 min-h-11 rounded-lg border border-line p-2 text-meta focus-ring"
            @focus="($event.target as HTMLInputElement).select()"
          >
        </label>
      </div>
    </template>
  </div>
</template>

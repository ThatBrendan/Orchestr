<script setup lang="ts">
import { ref, watch } from "vue";
import { useQueryClient } from "@tanstack/vue-query";
import * as joins from "@/services/joinLinks";
import { toAppError } from "@/lib/errors";
import { qk } from "@/composables/keys";
import AppButton from "@/components/ui/AppButton.vue";
const props = defineProps<{ projectId: string; readOnly: boolean }>();
const client = useQueryClient();
const access = ref<joins.JoinAccess>();
const loading = ref(false), busy = ref(false), reviewing = ref<string | null>(null);
const link = ref(""), feedback = ref(""), error = ref("");
const offset = ref(0);
let generation = 0;
async function load() {
  const current = ++generation;
  loading.value = true; error.value = "";
  try { const result = await joins.getJoinAccess(props.projectId, offset.value); if (current === generation) { access.value = result; link.value = result.link ?? ""; } }
  catch (e) { if (current === generation) error.value = toAppError(e).message; }
  finally { if (current === generation) loading.value = false; }
}
watch(() => props.projectId, () => { link.value = ""; access.value = undefined; offset.value = 0; void load(); }, { immediate: true });
async function disable() {
  if (busy.value) return;
  busy.value = true; error.value = "";
  try { await joins.disableJoinLink(props.projectId); link.value = ""; await load(); feedback.value = "Join link disabled."; }
  catch (e) { error.value = toAppError(e).message; }
  finally { busy.value = false; }
}
async function copy() {
  if (busy.value || props.readOnly) return;
  busy.value = true; error.value = ""; feedback.value = "";
  try {
    link.value = await joins.ensureJoinLink(props.projectId);
    try { await navigator.clipboard.writeText(link.value); feedback.value = "Invite link copied"; }
    catch { feedback.value = "Copy the invite link from the field below."; }
    await load();
  } catch (e) { error.value = toAppError(e).message; }
  finally { busy.value = false; }
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
</script>
<template>
  <section
    aria-labelledby="join-access-heading"
    class="space-y-4 min-w-0"
  >
    <h2
      id="join-access-heading"
      class="text-16 font-semibold"
    >
      Invite link
    </h2>
    <p class="text-13 text-muted">
      Approval required: On · Default role: Member
    </p>
    <p
      v-if="loading"
      role="status"
      class="text-14"
    >
      Loading access requests…
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
      :disabled="loading"
      @click="load"
    >
      Retry
    </AppButton>
    <template v-if="access">
      <p
        v-if="!access.active"
        class="text-14"
      >
        Copy an invite link so people can request access.
      </p>
      <div class="flex flex-wrap gap-2">
        <AppButton
          :disabled="busy || readOnly"
          :aria-busy="busy"
          @click="copy"
        >
          Copy invite link
        </AppButton>
        <AppButton
          v-if="access.active"
          variant="secondary"
          :loading="busy"
          :aria-busy="busy"
          :disabled="readOnly"
          @click="disable"
        >
          Disable link
        </AppButton>
      </div>
      <label
        v-if="link"
        class="block text-13"
      >Join link
        <input
          :value="link"
          readonly
          class="mt-1 block w-full min-w-0 rounded-lg border border-line p-2 text-13 focus-ring"
          @focus="($event.target as HTMLInputElement).select()"
        >
      </label>
      <h3
        v-if="access.pending_count"
        class="font-semibold text-14"
      >
        Join requests
      </h3>
      <article
        v-for="item in access.requests"
        :key="item.id"
        class="rounded-lg border border-line p-3 space-y-2 [overflow-wrap:anywhere]"
      >
        <p class="font-medium text-14">
          {{ item.display_name }}
        </p>
        <time
          :datetime="item.requested_at"
          class="text-13 text-muted"
        >Requested {{ new Date(item.requested_at).toLocaleString() }}</time>
        <div class="flex flex-wrap gap-2">
          <AppButton
            variant="secondary"
            :aria-label="`Decline ${item.display_name}`"
            :disabled="!!reviewing || readOnly"
            :aria-busy="reviewing === item.id"
            @click="review(item.id, false)"
          >
            Decline
          </AppButton>
          <AppButton
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
    </template>
    <p
      v-if="feedback"
      role="status"
      class="text-14"
    >
      {{ feedback }}
    </p>
  </section>
</template>

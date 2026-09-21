<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { DateTime } from "luxon";
import { useComments } from "@/composables/useComments";
import { toAppError } from "@/lib/errors";
import type { CommentResource, ResourceComment } from "@/types/comments";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
const props = defineProps<{ resource: CommentResource; timezone: string }>();
const { query, comments, create, remove } = useComments(() => props.resource);
const body = ref(""), error = ref(""), feedback = ref(""), deleting = ref<ResourceComment | null>(null), composer = ref<HTMLTextAreaElement>();
const busy = computed(() => create.isPending.value || remove.isPending.value);
const canComment = computed(() => query.data.value?.pages[0]?.can_comment ?? false);
let attempt: { body: string; id: string } | null = null;
watch(() => `${props.resource.type}:${props.resource.id}`, () => { body.value = ""; error.value = ""; feedback.value = ""; deleting.value = null; attempt = null; });
const stamp = (iso: string) => DateTime.fromISO(iso, { zone: props.timezone }).toFormat("d LLL yyyy, HH:mm");
async function post() {
  if (busy.value || !body.value.trim()) return;
  const resource = { ...props.resource }, text = body.value;
  if (!attempt || attempt.body !== text) attempt = { body: text, id: crypto.randomUUID() };
  error.value = ""; feedback.value = "";
  try {
    await create.mutateAsync({ resource, body: text, requestId: attempt.id });
    if (resource.id !== props.resource.id || resource.type !== props.resource.type) return;
    body.value = ""; attempt = null; feedback.value = "Comment added.";
    await nextTick(); composer.value?.focus();
  } catch (e) { if (resource.id === props.resource.id && resource.type === props.resource.type) error.value = toAppError(e).message; }
}
async function erase() {
  if (!deleting.value || busy.value) return;
  const resource = { ...props.resource }, id = deleting.value.id;
  error.value = ""; feedback.value = "";
  try {
    await remove.mutateAsync({ resource, id });
    if (resource.id !== props.resource.id || resource.type !== props.resource.type) return;
    deleting.value = null; feedback.value = "Comment removed.";
    await nextTick(); composer.value?.focus();
  } catch (e) { error.value = toAppError(e).message; }
}
</script>
<template>
  <section
    class="mt-6 border-t border-line pt-5 space-y-4"
    aria-label="Comments"
  >
    <h3 class="text-base font-semibold">
      Comments
    </h3>
    <p
      v-if="query.isPending.value"
      role="status"
      class="text-14 text-muted"
    >
      Loading comments…
    </p>
    <div
      v-else-if="query.isError.value"
      role="alert"
      class="space-y-2 text-14"
    >
      <p>{{ query.error.value?.message }}</p><AppButton
        variant="secondary"
        @click="query.refetch()"
      >
        Retry comments
      </AppButton>
    </div>
    <template v-else>
      <AppButton
        v-if="query.hasNextPage.value"
        variant="ghost"
        :loading="query.isFetchingNextPage.value"
        @click="query.fetchNextPage()"
      >
        Load earlier comments
      </AppButton>
      <p
        v-if="!comments.length"
        class="text-14 text-muted"
      >
        No comments yet.
      </p>
      <ol class="space-y-4">
        <li
          v-for="comment in comments"
          :key="comment.id"
          class="min-w-0 rounded-lg border border-line p-3"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <p class="text-14 font-medium [overflow-wrap:anywhere]">
                {{ comment.author_name }}
              </p><time
                :datetime="comment.created_at"
                :title="stamp(comment.created_at) + ' · ' + timezone"
                class="text-12 text-muted"
              >{{ stamp(comment.created_at) }} · {{ timezone }}</time>
            </div>
            <details
              v-if="comment.can_delete"
              class="shrink-0 text-13"
            >
              <summary
                class="cursor-pointer rounded px-2 py-2 focus-ring"
                :aria-label="'Actions for comment by ' + comment.author_name"
              >
                …
              </summary>
              <button
                class="min-h-11 px-2 text-danger focus-ring"
                :disabled="busy"
                @click="deleting = comment"
              >
                Delete comment
              </button>
            </details>
          </div>
          <p class="mt-2 whitespace-pre-wrap [overflow-wrap:anywhere] text-14">
            {{ comment.body }}
          </p>
        </li>
      </ol>
      <form
        v-if="canComment"
        class="space-y-2"
        @submit.prevent="post"
      >
        <label class="block text-14">Add a comment<textarea
          ref="composer"
          v-model="body"
          rows="3"
          maxlength="4000"
          :disabled="busy"
          class="mt-1 block w-full min-w-0 rounded-lg border border-line bg-surface px-3 py-2.5 text-14 focus-ring"
        /></label>
        <div class="flex justify-between items-center gap-2">
          <span class="text-12 text-muted">Plain text · {{ body.length }}/4000</span><AppButton
            type="submit"
            :loading="create.isPending.value"
            :disabled="busy || !body.trim()"
          >
            Comment
          </AppButton>
        </div>
      </form>
      <p
        v-else
        class="text-13 text-muted"
      >
        Comments are read-only while this project is archived.
      </p>
    </template>
    <p
      v-if="error && !deleting"
      role="alert"
      class="text-danger text-14"
    >
      {{ error }}
    </p>
    <p
      v-if="feedback"
      role="status"
      class="text-13 text-muted"
    >
      {{ feedback }}
    </p>
    <AppConfirmDialog
      :open="!!deleting"
      title="Delete comment?"
      :message="error || 'Remove this comment from the conversation?'"
      confirm-label="Delete comment"
      :loading="remove.isPending.value"
      danger
      @close="deleting = null; error = ''"
      @confirm="erase"
    />
  </section>
</template>

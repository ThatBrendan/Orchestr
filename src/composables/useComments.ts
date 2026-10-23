import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import { useAuthStore } from "@/stores/auth";
import { getComments, createComment, deleteComment } from "@/services/comments";
import type { CommentCursor, CommentResource } from "@/types/comments";
export function useComments(target: MaybeRefOrGetter<CommentResource>) {
  const auth = useAuthStore(), client = useQueryClient();
  const key = (r: CommentResource) => ["resource-comments", auth.userId, r.type, r.id];
  const query = useInfiniteQuery({
    queryKey: computed(() => key(toValue(target))),
    queryFn: ({ pageParam }) => getComments(toValue(target), pageParam),
    initialPageParam: null as CommentCursor | null,
    getNextPageParam: page => page.next_cursor ?? undefined,
    enabled: computed(() => auth.isAuthenticated),
    refetchInterval: 30_000,
  });
  // Pages arrive newest-first; each page is already chronological. Deduplicate boundary retries.
  const comments = computed(() => [...new Map((query.data.value?.pages.slice().reverse().flatMap(p => p.items) ?? []).map(c => [c.id, c])).values()]);
  const refresh = (resource: CommentResource) => client.invalidateQueries({ queryKey: key(resource), exact: true });
  const create = useMutation({ mutationFn: (input: { resource: CommentResource; body: string; requestId: string }) => createComment(input.resource, input.body, input.requestId), onSuccess: (_, input) => refresh(input.resource) });
  const remove = useMutation({ mutationFn: (input: { resource: CommentResource; id: string }) => deleteComment(input.resource, input.id), onSuccess: (_, input) => refresh(input.resource) });
  return { query, comments, create, remove };
}

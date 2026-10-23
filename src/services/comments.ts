import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { CommentResource, CommentCursor, CommentPage, ResourceComment } from "@/types/comments";
const args = (resource: CommentResource) => ({ p_resource_type: resource.type, p_resource_id: resource.id });
export async function getComments(resource: CommentResource, cursor: CommentCursor | null): Promise<CommentPage> {
  const { data, error } = await supabase.rpc("get_resource_comments", { ...args(resource), p_before_at: cursor?.created_at, p_before_id: cursor?.id });
  if (error) throw toAppError(error);
  return data as unknown as CommentPage;
}
export async function createComment(resource: CommentResource, body: string, requestId: string): Promise<ResourceComment> {
  const { data, error } = await supabase.rpc("create_resource_comment", { ...args(resource), p_body: body, p_id: requestId });
  if (error) throw toAppError(error);
  return data as unknown as ResourceComment;
}
export async function deleteComment(resource: CommentResource, comment: string) {
  const { error } = await supabase.rpc("delete_resource_comment", { ...args(resource), p_comment: comment });
  if (error) throw toAppError(error);
}

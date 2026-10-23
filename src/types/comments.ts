export type CommentableResourceType = "activity" | "decision";
export type CommentResource = { type: CommentableResourceType; id: string };
export type ResourceCommentRow = {
  id: string; project_id: string; resource_type: CommentableResourceType; resource_id: string;
  author_user_id: string; author_name: string; body: string; created_at: string; deleted_at: string | null;
};
export type ResourceComment = Omit<ResourceCommentRow, "deleted_at"> & { can_delete: boolean };
export type CommentCursor = { created_at: string; id: string };
export interface CommentPage { items: ResourceComment[]; next_cursor: CommentCursor | null; can_comment: boolean }

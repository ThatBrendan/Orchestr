import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { MemberRole } from "@/types/database";

export interface InvitationPreview {
  project_name: string;
  inviter_name: string | null;
  role: MemberRole;
  status: string;
}

export async function getInvitation(token: string): Promise<InvitationPreview | null> {
  const { data, error } = await supabase.rpc("get_invitation", { p_token: token });
  if (error) throw toAppError(error);
  return data?.[0] ?? null;
}

/** Returns the project_id joined. */
export async function acceptInvitation(token: string): Promise<string> {
  const { data, error } = await supabase.rpc("accept_invitation", { p_token: token });
  if (error) throw toAppError(error);
  return data as string;
}

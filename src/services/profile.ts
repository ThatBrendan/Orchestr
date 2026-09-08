import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { UserProfile } from "@/types/domain";

export async function getMyProfile(userId: string): Promise<UserProfile | null> {
  const { data, error } = await supabase.from("users").select("*").eq("id", userId).maybeSingle();
  if (error) throw toAppError(error);
  return data;
}

export async function updateMyDisplayName(userId: string, displayName: string): Promise<UserProfile> {
  const { data, error } = await supabase
    .from("users")
    .update({ display_name: displayName })
    .eq("id", userId)
    .select("*")
    .single();
  if (error) throw toAppError(error);
  return data;
}

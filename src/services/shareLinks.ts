import { supabase } from "@/lib/supabase";
import { config } from "@/config";
import { toAppError } from "@/lib/errors";

/** Only implemented policies belong here. Reserved future vocabulary grants nothing. */
export type ShareableResource = { type: "activity" | "decision"; id: string };
export type ShareResolution = { state: "sign_in" | "unavailable" } | {
  state: "authorized"; resource_type: "activity" | "decision" | "decision"; resource_id: string; project_id: string;
};
export interface ShareLink { active: boolean; url: string | null }
const args = (r: ShareableResource) => ({ p_resource_type: r.type, p_resource_id: r.id });
const url = (token: string) => new URL(`/s/${token}`, config.appUrl).href;
export async function getShareLink(resource: ShareableResource): Promise<ShareLink> {
  const { data, error } = await supabase.rpc("get_resource_share_link", args(resource));
  if (error) throw toAppError(error);
  const result = data as unknown as { active: boolean; token: string | null };
  return { active: result.active, url: result.active && result.token ? url(result.token) : null };
}
export async function createShareLink(resource: ShareableResource) {
  const { data, error } = await supabase.rpc("create_resource_share_link", args(resource));
  if (error) throw toAppError(error);
  return url(data);
}
export async function regenerateShareLink(resource: ShareableResource) {
  const { data, error } = await supabase.rpc("regenerate_resource_share_link", args(resource));
  if (error) throw toAppError(error);
  return url(data);
}
export async function disableShareLink(resource: ShareableResource) {
  const { error } = await supabase.rpc("disable_resource_share_link", args(resource));
  if (error) throw toAppError(error);
}
export async function resolveShareToken(token: string): Promise<ShareResolution> {
  const { data, error } = await supabase.rpc("resolve_shared_resource", { p_token: token });
  if (error) throw toAppError(error);
  return data as unknown as ShareResolution;
}

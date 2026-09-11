// Optional delivery endpoint. Persistence belongs exclusively to create_invitation.
// Email delivery is deferred until a production provider is verified/configured.
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "POST only" }, 405);
  try {
    const caller = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user }, error: authError } = await caller.auth.getUser();
    if (authError || !user) return json(req, { error: "Sign in required" }, 401);
    const body = await req.json();
    if (typeof body?.invitationId !== "string" || !/^[0-9a-f-]{36}$/i.test(body.invitationId)) {
      return json(req, { error: "invitationId must be a UUID" }, 400);
    }
    // Caller-scoped RLS allows only project organizers to inspect this invitation.
    const { data: invitation, error } = await caller.from("invitations").select("id,status,project_id")
      .eq("id", body.invitationId).single();
    if (error || !invitation) return json(req, { error: "Invitation unavailable" }, 403);
    const { data: membership } = await caller.from("project_members").select("id")
      .eq("project_id", invitation.project_id).eq("user_id", user.id)
      .eq("role", "organizer").eq("status", "active").is("deleted_at", null).maybeSingle();
    if (!membership) return json(req, { error: "Only an organizer can request delivery" }, 403);
    return json(req, { invitationId: invitation.id, emailed: false, message: "Email invite delivery deferred." });
  } catch {
    return json(req, { error: "Could not process delivery request" }, 400);
  }
});

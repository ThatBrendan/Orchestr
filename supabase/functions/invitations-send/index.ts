// invitations-send
// The ONLY MVP Edge Function (docs/SECURITY_RLS.md §11, TECHNICAL_ARCHITECTURE §14.2).
//
// Why an Edge Function: invitation rows are service_role-only (no client INSERT policy)
// because creation must (a) be rate-limited, (b) send a transactional email via an
// external provider using a secret. The invitation *acceptance* is the DB RPC
// public.accept_invitation() — not here.
//
// Flow:
//   1. CORS preflight
//   2. Parse + validate { projectId, email, role }
//   3. Authorize: caller (from their JWT) must be an organizer of projectId
//      -> checked with a CALLER-SCOPED client so RLS applies
//   4. Upsert the pending invitation with a SERVICE-SCOPED client
//   5. Send the email (provider call) — best-effort; failure does not roll back the row
//   6. Write an audit_log row (source='edge')
//
// Secrets (supabase secrets set): EMAIL_PROVIDER_API_KEY, EMAIL_FROM, APP_URL
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, ok, fail } from "../_shared/cors.ts";

interface Body {
  projectId: string;
  email: string;
  role?: "member" | "viewer";
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

Deno.serve(async (req) => {
  const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405, requestId);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // ---- parse -------------------------------------------------------------
  let body: Body;
  try {
    body = await req.json();
  } catch {
    return fail("bad_request", "Invalid JSON body", 400, requestId);
  }
  const role = body.role ?? "member";
  if (!body.projectId || !UUID_RE.test(body.projectId))
    return fail("bad_request", "projectId must be a uuid", 400, requestId);
  if (!body.email || !EMAIL_RE.test(body.email))
    return fail("bad_request", "email is not valid", 400, requestId);
  if (role !== "member" && role !== "viewer")
    return fail("bad_request", "role must be 'member' or 'viewer'", 400, requestId);
  const email = body.email.trim().toLowerCase();

  // ---- authorize (caller-scoped: RLS + helpers apply) -------------------
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userRes } = await caller.auth.getUser();
  if (!userRes?.user) return fail("unauthorized", "Sign in required", 401, requestId);

  // `app.is_organizer` is not PostgREST-exposed; authorize with a caller-scoped
  // membership read (RLS lets a member see project_members of their own projects).
  const { data: membership } = await caller
    .from("project_members")
    .select("id, role, status")
    .eq("project_id", body.projectId)
    .eq("user_id", userRes.user.id)
    .maybeSingle();
  if (!membership || membership.status !== "active" || membership.role !== "organizer")
    return fail("forbidden", "Only an organizer can invite", 403, requestId);

  // ---- naive rate limit: <= 25 pending invitations per project ---------
  const service = createClient(url, serviceKey);
  const { count: pendingCount } = await service
    .from("invitations")
    .select("id", { count: "exact", head: true })
    .eq("project_id", body.projectId)
    .eq("status", "pending");
  if ((pendingCount ?? 0) >= 25)
    return fail("rate_limited", "Too many pending invitations for this project", 429, requestId);

  // ---- already an active member? --------------------------------------
  const { data: existing } = await service
    .from("project_members")
    .select("id")
    .eq("project_id", body.projectId)
    .eq("email", email)
    .neq("status", "removed")
    .maybeSingle();
  if (existing) return fail("already_member", "That person is already in the project", 409, requestId);

  // ---- upsert the pending invitation (refresh if one exists) ----------
  await service
    .from("invitations")
    .update({ status: "revoked" })
    .eq("project_id", body.projectId)
    .eq("email", email)
    .eq("status", "pending");

  const token = crypto.randomUUID() + crypto.randomUUID().replace(/-/g, "");
  const { data: inv, error: invErr } = await service
    .from("invitations")
    .insert({
      project_id: body.projectId,
      email,
      role,
      token,
      invited_by: membership.id,
      expires_at: new Date(Date.now() + 14 * 864e5).toISOString(),
    })
    .select("id, token")
    .single();
  if (invErr || !inv) return fail("insert_failed", invErr?.message ?? "could not create invitation", 500, requestId);
  const callerMember = { id: membership.id };

  // ---- send the email (best effort) ----------------------------------
  const appUrl = Deno.env.get("APP_URL") ?? "http://localhost:5173";
  const link = `${appUrl}/invite/${inv.token}`;
  const providerKey = Deno.env.get("EMAIL_PROVIDER_API_KEY");
  let emailed = false;
  if (providerKey) {
    try {
      // Provider-specific; replace with your ESP. Example: Resend-style API.
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${providerKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: Deno.env.get("EMAIL_FROM") ?? "no-reply@example.com",
          to: email,
          subject: "You've been invited to a project on Orchestrio",
          text: `You've been invited to join a project. Open ${link} to accept.`,
        }),
      });
      emailed = r.ok;
    } catch (_e) {
      emailed = false;
    }
  }

  // ---- audit ---------------------------------------------------------
  await service.from("audit_log").insert({
    project_id: body.projectId,
    actor_user_id: userRes.user.id,
    actor_member_id: callerMember!.id,
    source: "edge",
    action: "create",
    entity_type: "invitations",
    entity_id: inv.id,
    after: { email, role, status: "pending" },
    request_id: requestId,
  });

  console.log(JSON.stringify({
    level: "info", fn: "invitations-send", request_id: requestId,
    project_id: body.projectId, emailed, msg: "invitation created",
  }));

  return ok({ invitationId: inv.id, emailed, link: providerKey ? undefined : link }, requestId);
});

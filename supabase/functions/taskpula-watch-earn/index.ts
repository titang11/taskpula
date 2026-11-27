import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respond({ error: "POST required." }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const authHeader = req.headers.get("Authorization");
  if (!url || !anon || !authHeader) return respond({ error: "Authentication is required." }, 401);
  const client = createClient(url, anon, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const { data: userData, error: authError } = await client.auth.getUser();
  if (authError || !userData.user) return respond({ error: "Your sign-in session is invalid or expired." }, 401);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return respond({ error: "Invalid request body." }, 400); }
  let result;
  if (body.action === "begin") {
    if (typeof body.campaign_id !== "string") return respond({ error: "Campaign is required." }, 400);
    result = await client.rpc("watch_begin_session", { p_campaign_id: body.campaign_id, p_client_nonce: crypto.randomUUID() + crypto.randomUUID() });
  } else if (body.action === "heartbeat") {
    if (typeof body.session_id !== "string" || typeof body.session_token !== "string" || typeof body.video_time !== "number" || typeof body.page_visible !== "boolean") return respond({ error: "Invalid playback heartbeat." }, 400);
    result = await client.rpc("watch_heartbeat", { p_session_id: body.session_id, p_session_token: body.session_token, p_video_time: body.video_time, p_page_visible: body.page_visible });
  } else if (body.action === "complete") {
    if (typeof body.session_id !== "string" || typeof body.session_token !== "string") return respond({ error: "Invalid viewing session." }, 400);
    result = await client.rpc("watch_complete_session", { p_session_id: body.session_id, p_session_token: body.session_token });
  } else return respond({ error: "Unknown Watch & Earn action." }, 400);
  if (result.error) return respond({ error: result.error.message || "The viewing request could not be verified." }, 400);
  return respond({ data: result.data });
});
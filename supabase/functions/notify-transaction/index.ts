import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const expectedSecret = req.headers.get("x-webhook-secret");
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: webhookSecret } = await supabase.rpc(
      "get_decrypted_secret",
      { secret_name: "notify_webhook_secret" },
    );
    if (!webhookSecret || expectedSecret !== webhookSecret) {
      return new Response("Unauthorized", { status: 401 });
    }

    // Every trigger (transactions/harvests/harvest_sales/
    // supplier_purchases) now builds its own title/body in SQL - this
    // function just relays it, so it doesn't need per-table formatting
    // logic duplicated in TypeScript.
    const { record } = await req.json();
    if (!record || !record.title) {
      return new Response("skipped", { status: 200 });
    }

    const { data: serviceAccountJson } = await supabase.rpc(
      "get_decrypted_secret",
      { secret_name: "firebase_service_account" },
    );
    if (!serviceAccountJson) {
      return new Response("Firebase service account not configured", {
        status: 500,
      });
    }
    const serviceAccount = JSON.parse(serviceAccountJson);

    const { data: tokenRows } = await supabase
      .from("device_tokens")
      .select("id, user_id, token")
      .neq("user_id", record.created_by ?? "");
    const tokens = (tokenRows ?? []) as {
      id: string;
      user_id: string;
      token: string;
    }[];
    if (tokens.length === 0) {
      return new Response("no recipients", { status: 200 });
    }

    const auth = new GoogleAuth({
      credentials: serviceAccount,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const client = await auth.getClient();
    const accessToken = (await client.getAccessToken()).token;

    const title = String(record.title);
    const body = String(record.body ?? "");
    // FCM data payload values must all be strings. Sent along so the
    // tapped notification can open NotificationDetailScreen without a
    // follow-up fetch - see lib/services/push_notifications.dart.
    const notifData: Record<string, string> = {
      kind: String(record.kind ?? ""),
      id: String(record.id ?? ""),
      title,
      body,
    };
    if (record.type) notifData.type = String(record.type);

    const sendUrl =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    const staleTokenIds: string[] = [];
    await Promise.all(
      tokens.map(async (row) => {
        const res = await fetch(sendUrl, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: row.token,
              notification: { title, body },
              data: notifData,
              android: { priority: "high" },
            },
          }),
        });
        if (res.status === 404 || res.status === 400) {
          const errBody = await res.text();
          if (
            errBody.includes("UNREGISTERED") ||
            errBody.includes("NOT_FOUND") ||
            errBody.includes("INVALID_ARGUMENT")
          ) {
            staleTokenIds.push(row.id);
          }
        }
      }),
    );

    if (staleTokenIds.length > 0) {
      await supabase.from("device_tokens").delete().in("id", staleTokenIds);
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error(e);
    return new Response(`error: ${e}`, { status: 500 });
  }
});

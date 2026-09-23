import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const TYPE_LABELS: Record<string, string> = {
  expense: "Expense",
  payroll: "Payroll",
  loan: "Loan given",
  advance: "Advance given",
  loan_repayment: "Loan repayment",
  advance_deduction: "Advance deduction",
};

function formatMoney(amount: number, currency: string): string {
  const symbol = currency === "SLSH" ? "Sh" : "$";
  const digits = currency === "SLSH" ? 0 : 2;
  return `${symbol}${amount.toLocaleString("en-US", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })}`;
}

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

    const { record } = await req.json();
    if (!record || record.type === "advance_deduction") {
      // No real cash moves for advance_deduction - not worth a push.
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

    const typeLabel = TYPE_LABELS[record.type as string] ?? record.type;
    const amount = formatMoney(
      Number(record.amount ?? 0),
      record.currency ?? "USD",
    );
    const note = (record.note ?? "").trim();
    const title = `${typeLabel}: ${amount}`;
    const body = note.length > 0 ? note : "Tap to view in Janatayn Farms.";

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

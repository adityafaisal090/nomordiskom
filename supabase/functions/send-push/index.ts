import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// Google OAuth2 access token generator from Service Account JSON
async function getFcmAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encodeBase64Url = (obj: Record<string, unknown>) => {
    const json = JSON.stringify(obj);
    const bytes = new TextEncoder().encode(json);
    return btoa(String.fromCharCode(...bytes))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  };

  const header = { alg: "RS256", typ: "JWT" };
  const encodedHeader = encodeBase64Url(header);
  const encodedClaim = encodeBase64Url(claim);
  const stringToSign = `${encodedHeader}.${encodedClaim}`;

  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = sa.private_key
    .replace(pemHeader, "")
    .replace(pemFooter, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(stringToSign)
  );

  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const jwt = `${stringToSign}.${encodedSignature}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const record = body.record; // Webhook payload from `notifications` INSERT

    if (!record || !record.user_id) {
      return new Response(JSON.stringify({ error: "Invalid webhook record payload" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(JSON.stringify({ error: "Missing Supabase env vars" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Fetch recipient's fcm_token from profiles
    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", record.user_id)
      .single();

    if (profileErr || !profile?.fcm_token) {
      return new Response(JSON.stringify({ message: "No FCM token found for user" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const serviceAccountSecret = Deno.env.get("FCM_SERVICE_ACCOUNT");

    if (!serviceAccountSecret) {
      console.warn("FCM_SERVICE_ACCOUNT secret not configured in Edge Function");
      return new Response(JSON.stringify({ message: "FCM_SERVICE_ACCOUNT not configured" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const sa = JSON.parse(serviceAccountSecret);
    const projectId = sa.project_id || Deno.env.get("FCM_PROJECT_ID") || "siagenda-1845d";
    const accessToken = await getFcmAccessToken(serviceAccountSecret);

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: profile.fcm_token,
            notification: {
              title: record.judul,
              body: record.isi_push || record.isi,
            },
            data: {
              agenda_id: String(record.agenda_id ?? ""),
              tipe: String(record.tipe ?? ""),
            },
            android: {
              priority: "HIGH",
              ttl: "18000s", // Pesan bertahan di antrean server selama 5 jam jika HP offline
              notification: {
                sound: "default",
                default_sound: true,
                default_vibrate_timings: true,
                channel_id: "mona_default_channel",
                notification_priority: "PRIORITY_HIGH",
                visibility: "PUBLIC",
              },
            },
          },
        }),
      }
    );

    const fcmResult = await fcmRes.json();
    if (!fcmRes.ok) {
      console.warn("FCM API responded with non-200 status (e.g. stale or unregistered token):", {
        status: fcmRes.status,
        result: fcmResult,
      });
      return new Response(JSON.stringify({ success: false, warning: "FCM token might be expired or invalid", fcmResult }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log("FCM Response:", fcmResult);

    return new Response(JSON.stringify({ success: true, fcmResult }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Edge function send-push caught exception:", err);
    // Return 200 with error details so webhook caller does not fail database transactions
    return new Response(JSON.stringify({ success: false, error: String(err) }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
});

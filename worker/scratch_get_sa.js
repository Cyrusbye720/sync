const refreshToken = "1//0g62DA08ayqfrCgYIARAAGBASNwF-L9Irrm8qHJdbvX-HjhdADfBtQwQ8u3nRTZNESbhDyQuW_fE0nPz1h1JQO08o-68yTAR1tTI";
const clientId = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const clientSecret = "76_p3-O5m1L3W3zF2M9_U1y_";
const projectId = "sync-alarm-app-2026";

async function run() {
  // 1. Refresh access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
    }),
  });
  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) {
    console.error("Token refresh failed:", tokenData);
    process.exit(1);
  }
  const accessToken = tokenData.access_token;
  console.log("Access token obtained.");

  // 2. List service accounts in project
  const saListRes = await fetch(`https://iam.googleapis.com/v1/projects/${projectId}/serviceAccounts`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const saListData = await saListRes.json();
  console.log("Existing SAs:", saListData);

  let saEmail = "";
  if (saListData.accounts && saListData.accounts.length > 0) {
    saEmail = saListData.accounts[0].email;
  } else {
    // Create service account
    const createRes = await fetch(`https://iam.googleapis.com/v1/projects/${projectId}/serviceAccounts`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        accountId: "sync-worker-sa",
        serviceAccount: {
          displayName: "SYNC Worker FCM Service Account",
        },
      }),
    });
    const createData = await createRes.json();
    console.log("Created SA:", createData);
    saEmail = createData.email;
  }

  if (!saEmail) {
    console.error("No service account email found or created.");
    process.exit(1);
  }

  // 3. Create private key for SA
  const keyRes = await fetch(`https://iam.googleapis.com/v1/projects/${projectId}/serviceAccounts/${saEmail}/keys`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      privateKeyType: "TYPE_GOOGLE_CREDENTIALS_FILE",
    }),
  });
  const keyData = await keyRes.json();
  if (!keyData.privateKeyData) {
    console.error("Key creation failed:", keyData);
    process.exit(1);
  }

  // privateKeyData is base64 encoded JSON
  const jsonStr = Buffer.from(keyData.privateKeyData, "base64").toString("utf-8");
  console.log("SERVICE_ACCOUNT_JSON_SUCCESS");
  console.log(jsonStr);
}

run().catch(console.error);

const encode = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const random = () => encode(crypto.getRandomValues(new Uint8Array(32)));
export async function createAuthorization(config, redirectUri) {
  const verifier = random();
  const state = random();
  const challenge = encode(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
  const url = new URL("/oauth2/authorize", config.authOrigin);
  url.search = new URLSearchParams({ response_type: "code", client_id: config.clientId, redirect_uri: redirectUri,
    scope: "openid", state, code_challenge: challenge, code_challenge_method: "S256" }).toString();
  return { url: url.href, transaction: { verifier, state, redirectUri, createdAt: Date.now() } };
}
export function validateCallback(search, transaction, redirectUri, now = Date.now()) {
  const params = new URLSearchParams(search);
  if (!transaction || typeof transaction.state !== "string" || typeof transaction.verifier !== "string" ||
      transaction.verifier.length !== 43 || !Number.isFinite(transaction.createdAt) ||
      now - transaction.createdAt > 600_000 || now < transaction.createdAt ||
      transaction.redirectUri !== redirectUri || params.getAll("state").length !== 1 ||
      params.get("state") !== transaction.state) throw new Error("Sign-in expired or could not be verified. Please sign in again.");
  if (params.has("error")) throw new Error("Sign-in was not completed. Please try again.");
  const code = params.get("code");
  if (!code || code.length > 4096 || params.getAll("code").length !== 1) throw new Error("Invalid sign-in response. Please try again.");
  return code;
}
export async function exchangeCode(config, code, transaction) {
  const response = await fetch(new URL("/oauth2/token", config.authOrigin), {
    method: "POST", credentials: "omit", cache: "no-store", redirect: "error",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "authorization_code", client_id: config.clientId,
      code, code_verifier: transaction.verifier, redirect_uri: transaction.redirectUri }),
  });
  if (!response.ok) throw new Error("Sign-in could not be completed. Please try again.");
  const result = await response.json();
  if (typeof result.access_token !== "string" || result.token_type?.toLowerCase() !== "bearer" ||
      !Number.isFinite(result.expires_in) || result.expires_in <= 0 || result.expires_in > 600) throw new Error("Unexpected sign-in response.");
  // Only the short-lived access token is retained, in memory. Ignore ID and refresh tokens.
  return { token: result.access_token, expiresAt: Date.now() + result.expires_in * 1000 };
}

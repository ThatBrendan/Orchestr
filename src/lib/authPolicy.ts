/** Shared auth rules. Keep the existing signup minimum; verify hosted policy before release. */
export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_HINT = `At least ${PASSWORD_MIN_LENGTH} characters.`;
export const RECOVERY_SENT = "If an account exists for that email, we've sent password reset instructions.";

export function passwordError(password: string, confirmation?: string): string | null {
  if (password.length < PASSWORD_MIN_LENGTH) return `Use a password of at least ${PASSWORD_MIN_LENGTH} characters.`;
  if (confirmation !== undefined && password !== confirmation) return "Passwords do not match.";
  return null;
}

function hasUnsafeCharacters(value: string) {
  return /[\\\s]/.test(value) || [...value].some(char => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127);
}

/** Only application and invitation destinations; reject encoded tricks and auth loops. */
export function safeRedirect(raw: unknown): string | null {
  if (typeof raw !== "string" || hasUnsafeCharacters(raw)) return null;
  try {
    const decoded = decodeURIComponent(raw);
    if (hasUnsafeCharacters(decoded)) return null;
    const url = new URL(raw, "https://auth.invalid");
    if (url.origin !== "https://auth.invalid" || !raw.startsWith("/")) return null;
    if (!/^\/(?:(?:app|admin)(?:\/|$)|invite\/[^/]+$)/.test(url.pathname)) return null;
    if (url.pathname.includes("%") || /(?:^|\/)\.{1,2}(?:\/|$)/.test(raw.split(/[?#]/)[0]!)) return null;
    return url.pathname + url.search + url.hash;
  } catch { return null; }
}

export function authCallbackUrl(appUrl: string, redirect?: unknown, mode?: "signup" | "recovery") {
  const url = new URL("/auth/callback", appUrl);
  const destination = safeRedirect(redirect);
  if (destination) url.searchParams.set("redirect", destination);
  if (mode) url.searchParams.set("mode", mode);
  return url.href;
}

/** Capture before the SDK consumes the URL. Never retain credentials or error descriptions. */
export function readAuthLink(href: string) {
  const url = new URL(href);
  const hash = new URLSearchParams(url.hash.slice(1));
  return {
    pathname: url.pathname,
    redirect: safeRedirect(url.searchParams.get("redirect")),
    isLink: url.searchParams.has("code") || hash.has("access_token"),
    hasError: [url.searchParams, hash].some(p => p.has("error") || p.has("error_code")),
    recovery: url.pathname === "/reset-password" || url.searchParams.get("mode") === "recovery" || hash.get("type") === "recovery",
    signup: url.searchParams.get("mode") === "signup" || hash.get("type") === "signup",
  };
}

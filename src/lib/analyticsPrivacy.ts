import { PUBLIC_ORIGIN, PUBLIC_PAGES } from "../publicSite";

/** Allowlist pages; never forward tokens, UUIDs, arbitrary slugs, queries or hashes. */
export function analyticsPath(raw: string): string | null {
  try {
    const path = new URL(raw, PUBLIC_ORIGIN).pathname.replace(/\/+$/, "") || "/";
    if (Object.hasOwn(PUBLIC_PAGES, path)) return path;
    if (path === "/app" || path.startsWith("/app/")) return "/app";
    return null;
  } catch { return null; }
}

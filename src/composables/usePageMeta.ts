import { onMounted } from "vue";
import { APP_NAME } from "@/config";

export const DEFAULT_TITLE = `${APP_NAME} — Plan together. Execute clearly.`;
export const DEFAULT_DESCRIPTION =
  "Orchestr brings costs, responsibilities, commitments, deadlines, logistics and progress into one shared workspace — so complex plans become coordinated execution.";

interface PageMeta {
  title?: string;
  description?: string;
  /** Full canonical URL, if known. */
  url?: string;
}

function upsertMeta(selector: string, attr: "name" | "property", key: string, content: string) {
  let el = document.head.querySelector<HTMLMetaElement>(selector);
  if (!el) {
    el = document.createElement("meta");
    el.setAttribute(attr, key);
    document.head.appendChild(el);
  }
  el.setAttribute("content", content);
}

/**
 * Per-view document metadata for the SPA (spec §18). No SSR — this is a
 * client-side title/description/OpenGraph setter, sufficient for a public SPA.
 */
export function usePageMeta(meta: PageMeta) {
  const title = meta.title ?? DEFAULT_TITLE;
  const description = meta.description ?? DEFAULT_DESCRIPTION;

  // Runs after the router's afterEach (component mount is later in the cycle),
  // so a view that calls usePageMeta() wins over the meta.title fallback.
  onMounted(() => {
    document.title = title;
    upsertMeta('meta[name="description"]', "name", "description", description);
    upsertMeta('meta[property="og:title"]', "property", "og:title", title);
    upsertMeta('meta[property="og:description"]', "property", "og:description", description);
    upsertMeta('meta[property="og:type"]', "property", "og:type", "website");
    if (meta.url) upsertMeta('meta[property="og:url"]', "property", "og:url", meta.url);
    upsertMeta('meta[name="twitter:card"]', "name", "twitter:card", "summary_large_image");
  });
}

/** Reset description to the product default (used by the router for app routes). */
export function resetPageMeta() {
  upsertMeta('meta[name="description"]', "name", "description", DEFAULT_DESCRIPTION);
}

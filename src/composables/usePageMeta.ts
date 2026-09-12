import { config } from "@/config";
import { APP_NAME, pageMetadata } from "@/publicSite";
export { DEFAULT_TITLE, DEFAULT_DESCRIPTION } from "@/publicSite";

export function setRouteMeta(path: string, fallbackTitle?: string) {
  const meta = pageMetadata(path, config.env === "production", fallbackTitle);
  document.title = meta.title;
  document.head.querySelectorAll('[data-page-meta], meta[name="description"], meta[name="robots"], meta[property^="og:"], meta[name^="twitter:"], link[rel="canonical"]').forEach((el) => el.remove());
  const tags = [
    ["name", "description", meta.description], ["name", "robots", meta.robots],
    ["property", "og:title", meta.title], ["property", "og:description", meta.description],
    ["property", "og:type", "website"], ["property", "og:site_name", APP_NAME],
    ["name", "twitter:card", "summary"], ["name", "twitter:title", meta.title],
    ["name", "twitter:description", meta.description],
  ];
  if (meta.canonical) tags.push(["property", "og:url", meta.canonical]);
  for (const [attr, key, value] of tags) {
    const el = document.createElement("meta");
    el.setAttribute(attr!, key!);
    el.content = value!;
    el.dataset.pageMeta = "";
    document.head.append(el);
  }
  if (meta.canonical) {
    const link = document.createElement("link");
    link.rel = "canonical";
    link.href = meta.canonical;
    link.dataset.pageMeta = "";
    document.head.append(link);
  }
  if (meta.structuredData) {
    const script = document.createElement("script");
    script.type = "application/ld+json";
    script.dataset.pageMeta = "";
    script.textContent = JSON.stringify(meta.structuredData);
    document.head.append(script);
  }
}

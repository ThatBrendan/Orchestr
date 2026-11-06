import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";

const manifest = JSON.parse(await readFile("dist/manifest.webmanifest", "utf8"));
assert.equal(manifest.name, "Orchestrio");
assert.equal(manifest.short_name, "Orchestrio");
assert.equal(manifest.start_url, "/app");
assert.equal(manifest.scope, "/");
assert.equal(manifest.display, "standalone");
assert.equal(manifest.theme_color, "#ffffff");
assert.equal(manifest.background_color, "#ffffff");
assert(manifest.icons.some((icon) => icon.sizes === "192x192" && icon.purpose === "any"));
assert(manifest.icons.some((icon) => icon.sizes === "512x512" && icon.purpose === "any"));
assert(manifest.icons.some((icon) => icon.sizes === "512x512" && icon.purpose === "maskable"));
for (const icon of manifest.icons) {
  const bytes = await readFile(`dist${icon.src}`);
  assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  assert.equal(`${width}x${height}`, icon.sizes);
}
const html = await readFile("dist/index.html", "utf8");
assert(/<link rel="manifest" href="\/manifest\.webmanifest"\s*\/>/.test(html));
assert(/<link rel="apple-touch-icon" href="\/icons\/orchestrio-180\.png"\s*\/>/.test(html));
await access("dist/offline.html");
const offline = await readFile("dist/offline.html", "utf8");
assert(offline.includes('name="robots" content="noindex, nofollow"'));
assert(offline.includes("does not save project changes while offline"));
const worker = await readFile("dist/sw.js", "utf8");
const registration = await readFile("src/components/pwa/PwaExperience.vue", "utf8");
assert(registration.includes('config.env === "production" || config.env === "staging"'));
assert(registration.includes("window.isSecureContext"));
assert(!worker.includes("__PRECACHE_URLS__"));
assert(!worker.includes("__PRECACHE_VERSION__"));
assert(worker.includes('request.mode === "navigate"'));
assert(worker.includes('url.pathname.startsWith("/app/")'));
assert(worker.includes('url.pathname.startsWith("/admin/")'));
assert(worker.includes('!PRECACHE_URLS.includes(url.pathname)'));
assert(worker.includes('caches.open(CACHE_NAME)'));
assert(!worker.includes("caches.match("));
assert(!worker.includes("cache.put("));
assert(worker.includes('request.method !== "GET"'));
assert(worker.includes('name.startsWith("orchestrio-static-")'));
assert(!worker.includes("supabase"));
assert(!worker.includes("Authorization"));
const precache = JSON.parse(worker.match(/const PRECACHE_URLS = (\[[^;]+\]);/)[1]);
const publicShellAssets = new Set([
  "/spa.html", "/offline.html", "/manifest.webmanifest", "/orchestrio-favicon.svg",
  "/icons/orchestrio-180.png", "/icons/orchestrio-192.png", "/icons/orchestrio-512.png", "/icons/orchestrio-maskable-512.png",
]);
assert(precache.filter((item) => !item.startsWith("/assets/")).every((item) => publicShellAssets.has(item)));
for (const item of precache) await access(`dist${item}`);
for (const asset of precache.filter((item) => item.startsWith("/assets/"))) assert(/-[\w-]+\./.test(asset), `Expected a hashed Vite asset: ${asset}`);
const digest = createHash("sha256").update(JSON.stringify(precache));
for (const asset of precache) digest.update(await readFile(`dist${asset}`));
assert(worker.includes(`orchestrio-static-${digest.digest("hex").slice(0, 12)}`));
assert(worker.includes('name !== CACHE_NAME'));
console.log("PASS: PWA manifest, PNG icon sizes, shell links, offline page, static-only precache and route fallback policy.");

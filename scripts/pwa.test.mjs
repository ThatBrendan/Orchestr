import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { build } from "vite";

async function load(entry) {
  const result = await build({ configFile: false, logLevel: "silent", build: { write: false, minify: false, lib: { entry, formats: ["es"] } } });
  const output = Array.isArray(result) ? result[0] : result;
  return import(`data:text/javascript;base64,${Buffer.from(output.output.find(item => item.type === "chunk").code).toString("base64")}`);
}

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

const pwa = await load("src/lib/pwaInstall.ts");
assert.equal(pwa.isStandaloneMode(true), true);
assert.equal(pwa.isStandaloneMode(false, true), true);
assert.equal(pwa.isStandaloneMode(false, false), false);
assert.equal(pwa.isIosDevice("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", "iPhone", 5), true);
assert.equal(pwa.isIosDevice("Mozilla/5.0 (Macintosh; Intel Mac OS X)", "MacIntel", 5), true);
assert.equal(pwa.isIosDevice("Mozilla/5.0 (Linux; Android 14)", "Linux armv8l", 5), false);
assert.equal(pwa.isIosSafari("Mozilla/5.0 Version/17.0 Safari/605.1.15"), true);
assert.equal(pwa.isIosSafari("Mozilla/5.0 CriOS/119 Mobile Safari/605.1.15"), false);
assert.equal(pwa.isIosSafari("Mozilla/5.0 FxiOS/120 Mobile Safari/605.1.15"), false);
assert.equal(pwa.isIosSafari("Mozilla/5.0 EdgiOS/120 Mobile Safari/605.1.15"), false);
assert.equal(pwa.isIosSafari("Mozilla/5.0 OPiOS/120 Mobile Safari/605.1.15"), false);
assert.equal(pwa.isIosSafari("Mozilla/5.0 DuckDuckGo/120 Mobile Safari/605.1.15"), false);

const values = new Map();
const storage = {
  getItem: key => values.get(key) ?? null,
  setItem: (key, value) => values.set(key, value),
};
const now = 1_800_000_000_000;
pwa.writeInstallDismissed(storage, now);
assert.equal(pwa.readInstallDismissed(storage, now + 29 * 24 * 60 * 60 * 1000), true);
assert.equal(pwa.readInstallDismissed(storage, now + 31 * 24 * 60 * 60 * 1000), false);

const composable = await readFile("src/composables/usePwaInstall.ts", "utf8");
assert(composable.includes('window.addEventListener("beforeinstallprompt", onBeforeInstallPrompt)'));
assert(composable.includes('window.addEventListener("appinstalled", onAppInstalled)'));
assert(composable.includes("await prompt.prompt()"));
assert(composable.includes("choice.outcome === \"dismissed\""));
assert(composable.includes("nativeAvailable.value || isIos.value"));

const dashboard = await readFile("src/views/DashboardView.vue", "utf8");
assert(dashboard.includes("Take Orchestrio with you."));
assert(dashboard.includes("pwa.canOfferDashboardCard.value"));
assert(dashboard.includes("Dismiss installation card"));
assert(dashboard.includes("pwa.dismissInstall()"));
const settings = await readFile("src/views/SettingsView.vue", "utf8");
assert(settings.includes("App installation"));
assert(settings.includes("v-if=\"!pwa.isInstalled.value\""));
assert(settings.includes("handleInstallAction"));
assert(settings.includes("This browser does not offer automatic installation."));
const experience = await readFile("src/components/pwa/PwaExperience.vue", "utf8");
assert(experience.includes("pwa.initializePwaInstall()"));
assert(experience.includes("pwa.destroyPwaInstall()"));
const instructions = await readFile("src/components/pwa/PwaInstallInstructions.vue", "utf8");
assert(instructions.includes('import { isIosSafari } from "@/lib/pwaInstall"'));
assert(instructions.includes("return !isIosSafari(navigator.userAgent);"));
assert(!instructions.includes("@after-close"));
assert(instructions.includes("If you are using another iOS browser"));
assert(instructions.includes("It is usually in the browser toolbar"));
console.log("PASS: installation detection, dismissal expiry, native/app-installed listeners, dashboard visibility, settings access and iOS guidance wiring.");

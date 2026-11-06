/* Build script replaces the token with hashed static asset paths. */
const CACHE_NAME = "orchestrio-static-__PRECACHE_VERSION__";
const PRECACHE_URLS = "__PRECACHE_URLS__";

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter((name) => name.startsWith("orchestrio-static-") && name !== CACHE_NAME).map((name) => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        return await fetch(request);
      } catch {
        const cache = await caches.open(CACHE_NAME);
        if (url.pathname === "/app" || url.pathname.startsWith("/app/") || url.pathname === "/admin" || url.pathname.startsWith("/admin/")) {
          return (await cache.match("/spa.html")) ?? (await cache.match("/offline.html"));
        }
        return (await cache.match("/offline.html")) ?? new Response("You’re offline. Reconnect to load Orchestrio.", { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" } });
      }
    })());
    return;
  }

  // Only immutable build assets and explicit public app-shell assets are eligible.
  // API, auth, storage, project, invitation and all other requests pass through untouched.
  if (!PRECACHE_URLS.includes(url.pathname) || (!url.pathname.startsWith("/assets/") && !url.pathname.startsWith("/icons/") && !["/manifest.webmanifest", "/orchestrio-favicon.svg"].includes(url.pathname))) return;
  event.respondWith(caches.open(CACHE_NAME).then((cache) => cache.match(request)).then((cached) => cached ?? fetch(request)));
});

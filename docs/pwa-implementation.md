# Orchestrio PWA: Phase 1

## Architecture

The root web manifest is `public/manifest.webmanifest`. It starts at `/app`, uses `/` scope and standalone display. This launches the existing authenticated app route, whose current guard directs signed-out visitors through the established sign-in flow. PNG icons in `public/icons/` use the existing Orchestrio ring mark. `index.html` links the manifest and the 180px Apple home-screen icon.

`public/sw.js` is a small custom service worker. `scripts/build-public.mjs` writes its precache list after Vite and public prerendering have produced the hashed assets and `/spa.html`. The worker precaches that SPA shell, the offline page, the manifest, icons, favicon and immutable `/assets/` build files. It never caches HTML navigations, API responses, Supabase traffic or user data. Navigation requests are network-first; if an `/app` or `/admin` route cannot reach the network, the cached SPA shell opens. Other failed navigations show `public/offline.html`. Non-precache requests are untouched.

The worker registers only for secure production or isolated staging origins. A waiting update stays in the background until the user chooses “Update ready · Refresh”. The worker then activates and the page reloads at that user action. Activation removes older Orchestrio static caches. No active page is forcibly refreshed.

## Offline limitations

Phase 1 is online-first. Project data, authentication, invitations and writes still require a network. No user-specific response, authentication token or project content is cached. Before the service worker finishes its first installation, offline fallbacks are not available; the app behaves like the ordinary online application. After installation, the app displays a connection banner while offline, notes that already displayed data may be out of date, and states that changes are not saved offline. There is no offline editing, queue, background sync or push notification support.

## Installation

- **Android / supported desktop Chromium:** use the discreet “Install Orchestrio” option when the browser exposes its native install prompt. The browser’s own install action is also available.
- **iPhone / iPad Safari:** tap “Add to Home Screen”, then use Safari’s Share button and choose “Add to Home Screen”. The install option is hidden when the app is already running in standalone mode.

Dismissed install hints are remembered in local storage. `appinstalled` and standalone display mode suppress the hint after installation.

## Testing

Run `npm run typecheck`, `npm run build`, `npm run seo:test`, `npm run pwa:test` and `npm run lint`. The build emits `dist/manifest.webmanifest`, icons, `dist/offline.html` and a generated `dist/sw.js` with the current content-hashed asset list. `npm run dev` does not register the worker. Browser installation and worker registration can be exercised from an approved Vercel preview configured with the isolated staging backend, or from production. Do not bypass the repository's environment safeguards for local testing.

Manual device checks:

1. On iPhone/iPad Safari, choose Share → Add to Home Screen, then launch Orchestrio from its icon.
2. On Android Chrome, install from the native prompt or browser menu, then launch it from the home screen.
3. On desktop Chrome or Edge, use the address-bar install control or browser menu.
4. In the installed app, sign in and open an existing project; verify normal auth and route behavior.
5. Go offline. Confirm the connection notice appears, `/app` opens only the app shell, and project data/actions require a connection. Open a public page in a new navigation and confirm the offline message appears.
6. Reconnect and confirm the app returns to normal. Deploy a later build and confirm an update notice appears; choose refresh to apply it.

This repository implementation has not been verified on physical iOS or Android devices. Browser/device installation and offline behavior must be confirmed on those platforms before claiming device-level verification.

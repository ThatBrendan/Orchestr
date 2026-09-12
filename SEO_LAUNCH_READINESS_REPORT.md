# SEO and launch readiness — 12 September 2026

Implemented on `dev`. No commit, push, merge, deployment, production service mutation, or Supabase change performed. Browser/mobile and deployed Preview checks remain outstanding; this is not a production approval.

## Existing architecture audit

Before changes, `index.html` supplied one generic title/description, partial Open Graph tags and a large-image Twitter card without an image. The app container was empty. `usePageMeta` updated metadata after JavaScript ran; the router supplied title fallbacks. The homepage used deployment-specific `config.appUrl` for its social URL. PublicInfoView maintained separate metadata. There were no canonical links, robots file, sitemap, JSON-LD, noindex policy or analytics. Unknown URLs already reached a minimal branded view but lacked a heading/account CTA and the universal hosting rewrite returned the homepage shell for everything.

The favicon/logo already used Orchestrio branding. No manifest exists. No public-facing legacy Vercel-domain link or localhost link was found. Homepage, About, marketing header/footer, product preview, auth views, routing, Vite/Vercel configuration and public assets were inspected.

## SEO architecture

- **Metadata approach:** `src/publicSite.ts` owns route titles/descriptions and public identity. Router navigation applies metadata through `setRouteMeta`, clearing stale tags and homepage JSON-LD. The build renders the existing Vue homepage/About/Privacy/Terms components into static HTML using Vue's renderer. Login/signup receive static metadata with a client-rendered form. No SSR server, Nuxt migration or SEO framework.
- **Canonical approach:** fixed authoritative `https://orchestrio.io`, independent of environment-specific auth redirect URLs. Canonicals strip queries, fragments and trailing slashes. Only the six allowlisted routes receive canonicals. Preview and development builds are noindex; production public pages are indexable.
- **SPA limitations:** interactive behavior, auth forms and private app content still need JavaScript. Public content is already in the response and the client mounts after initial route resolution. No authenticated content is prerendered or fetched during rendering. Vercel Preview must verify the hosting rules; Vite preview does not emulate Vercel's custom-404 behavior.
- `vercel.json` now serves clean public HTML URLs, limits SPA rewrites to app/admin/auth/invite/access-denied and leaves unmatched requests to Vercel's `404.html` handling. This is a proposed repository routing change, not a live infrastructure change. [Vercel custom 404 documentation](https://vercel.com/kb/guide/custom-404-page), [Vite routing documentation](https://vercel.com/docs/frameworks/frontend/vite).

## Page metadata

Indexable below means **production**. All routes are noindex in development/staging builds.

| Route | Title | Description | Canonical | Indexable |
|---|---|---|---|---|
| `/` | Orchestrio — Planning and Execution Workspace | Orchestrio brings activities, responsibilities, timelines, budgets, people and recurring processes into one place so groups and teams can plan together and execute clearly. | https://orchestrio.io/ | Yes |
| `/about` | About Orchestrio &#124; Orchestrio | Learn why Orchestrio brings scattered plans into one workspace for groups and teams to coordinate people, activities, timelines and costs. | https://orchestrio.io/about | Yes |
| `/privacy` | Privacy Policy &#124; Orchestrio | Read how Orchestrio handles account and project information, service providers and privacy enquiries. | https://orchestrio.io/privacy | Yes |
| `/terms` | Terms of Service &#124; Orchestrio | Read the terms for using Orchestrio, including account responsibilities, shared content and acceptable use. | https://orchestrio.io/terms | Yes |
| `/login` | Log in &#124; Orchestrio | Log in to your Orchestrio workspace. | https://orchestrio.io/login | No |
| `/signup` | Sign up &#124; Orchestrio | Create your Orchestrio account to plan and coordinate with your group or team. | https://orchestrio.io/signup | No |

Private routes, callback/invitation routes, access-denied and unknown routes receive `noindex, nofollow`, no canonical and no JSON-LD. Existing private route title fallbacks remain.

## Search files

Generated into `dist` on every `npm run build`, rather than duplicated in `public`:

- **robots.txt:** production allows `/`, disallows `/app`, `/admin`, `/auth/`, `/invite/`, and declares the production sitemap. Non-production disallows all crawling. Auth/RLS remains the security boundary.
- **sitemap.xml:** canonical public pages only; no fabricated modification dates. Login/signup are excluded because they are account utilities.

Sitemap URLs:

1. https://orchestrio.io/
2. https://orchestrio.io/about
3. https://orchestrio.io/privacy
4. https://orchestrio.io/terms

## Structured data

Homepage only: `@context: https://schema.org`, with an `@graph` containing:

- **Organization:** `@type: Organization`, `name: Orchestrio`, `url: https://orchestrio.io`, `email: admin@orchestrio.io`, `logo: https://orchestrio.io/orchestrio-favicon.svg`.
- **SoftwareApplication:** `@type: SoftwareApplication`, `name: Orchestrio`, `applicationCategory: BusinessApplication`, `operatingSystem: Web`, `url: https://orchestrio.io`, `description`: the full homepage description in the table above.

No ratings, offers, prices, legal entity, address, registration number, telephone or social accounts invented. JSON parsing and key fields verified.

## Social metadata

- **Open Graph:** title, description, URL for canonical routes, type `website`, site name `Orchestrio`.
- **Twitter/X:** `summary`, title, description.
- **Social image:** none added. Only existing vector brand icons are available; these are not a suitable large sharing image. Removed the unsupported large-image-card claim. `og:image` and `twitter:image` deliberately omitted rather than publishing a broken or unsuitable image. A suitable approved public sharing asset remains an optional follow-up.

## Image accessibility and public clarity

- **Images audited:** marketing header/footer logos, login/signup/invitation logos, official favicon and product preview.
- **Alt text added:** none needed. Header/auth logos already have meaningful Orchestrio alt text; linked logos have accessible names.
- **Decorative images corrected:** none needed. Footer logo already has empty alt with an accessible home link. Product preview is semantic HTML, not a screenshot; static icon SVGs are decorative.
- Automated rendered-image checks verify alt presence and asset existence. Vue serializes the footer's empty alt as bare `alt`, which is valid empty-attribute HTML.
- Homepage explains the coordination problem and capabilities; About explains origin, audience and use. Existing headings/copy were retained. No hidden SEO text, keyword stuffing, AI landing pages or llms.txt.

## 404

- **Route handling:** existing final Vue catch-all retained. Build emits `404.html` with noindex and branded content. Vercel should serve it with HTTP 404 for unmatched public URLs. Unknown URLs within private namespaces still resolve through the SPA and show its client-side 404.
- **CTAs:** Go home plus Log in, or Dashboard for an authenticated visitor.
- **Accessibility/mobile:** added an h1 and clear explanation; actions wrap with spacing and existing touch-target styles. Actual 375/430/768/desktop rendering is **NOT RUN** because Computer Use permissions were denied.
- Local Vite preview returns 200/home HTML for unknown URLs; this is its SPA fallback, not proof of Vercel behavior. Direct `/404.html` returns the correct static content. Deployed HTTP status verification remains **NOT RUN**.

## Forms and spam protection

- **Forms audited:** signup, login, invitation accept/decline, callback. No public password-reset UI, contact form, newsletter or anonymous feedback form exists.
- **Validation changes:** retained required email/password, browser email validation and eight-character signup minimum. Added explicit busy guards to login/signup and accept/decline handlers. Existing disabled/loading AppButton behavior retained.
- **Error handling:** public password-auth requests now map provider codes to safe, useful AppError messages (invalid credentials, unconfirmed email, weak password, invalid email, signup unavailable and rate limits). Unknown provider errors use a generic message. Invitation errors retain existing AppError mapping.
- **Duplicate submission:** busy/pending checks plus existing disabled/loading states. No authentication or authorization flow rewritten.
- **Public anonymous submission surfaces:** none outside account authentication. No public anonymous submission surface currently requires CAPTCHA/spam protection.
- **Protection implemented:** validation and submit guards; existing Supabase authentication boundary.
- **Protection deferred:** CAPTCHA and hosted rate-limit changes.
- **Reason:** no demonstrated bot incident and no anonymous contact/newsletter endpoint. Supabase Auth provides endpoint rate limits; hosted production limits, email confirmation and delivery settings cannot be inferred from local config. Local config disables confirmations for local development; it was not changed. Manually review hosted production Auth settings before launch. [Supabase rate limits](https://supabase.com/docs/guides/auth/rate-limits), [CAPTCHA options](https://supabase.com/docs/guides/auth/auth-captcha).

## Analytics and privacy

- **Provider:** Vercel Web Analytics (`@vercel/analytics`), enabled by code only when `VITE_APP_ENV` is production and the browser origin is exactly `https://orchestrio.io`.
- **Production configuration required:** manually enable Web Analytics in the existing Vercel project. Confirm plan support: custom events require Pro or Enterprise. No credentials, IDs, subscription changes or dashboard changes made. [Custom event requirements](https://vercel.com/docs/analytics/custom-events).
- **Page views:** manual router tracking after successful navigation, auto-tracking disabled. Public pages retain allowlisted paths; all app URLs aggregate to `/app`. Admin, invitation, callback and unknown URLs are excluded. Basic traffic source reporting comes from the provider; `strict-origin` referrer policy limits the referring URL. [Vercel traffic reporting](https://vercel.com/docs/analytics/using-web-analytics).
- **PII excluded:** API accepts event names only, no properties. No names, emails, titles, amounts, notes, booking references or UUIDs. Queries/fragments are removed; private app paths are grouped. Custom-event URL context is always the generic production `/app` URL. Analytics failures do not fail successful write actions.
- **Privacy wording:** replaced the statement that no analytics service exists with factual conditional Vercel analytics copy describing page visits, traffic sources, action events and data exclusions. Official contact remains admin@orchestrio.io. No legal compliance or cookie-consent assertion added. [Vercel privacy controls](https://vercel.com/docs/analytics/privacy-policy).

Exact event names and semantics:

| Event | Trigger |
|---|---|
| `signup_started` | First valid signup submission per mounted form |
| `signup_completed` | Signup immediately returns an authenticated session |
| `signup_confirmation_requested` | Successful signup response still requires email confirmation |
| `login_completed` | Successful password login |
| `project_created` | Successful project creation |
| `member_invited` | Invitation successfully persisted; does not claim email delivery |
| `invitation_accepted` | Successful invitation acceptance |
| `activity_created` | Successful activity creation |
| `task_created` | Successful task creation |
| `cost_split_saved` | Successful explicit split save with activity creation/update or actual cost; includes updates, hence “saved” |
| `payment_recorded` | Successful payment record creation; does not imply payment settled |
| `activity_completed` | Successful completion command for activity, occurrence or actual-cost completion |

Events are client-side operational counts, not audit records or unique-user counts. Confirmation in a later email callback is not correlated to the original signup; `signup_completed` therefore does not measure the full confirmed-email funnel. Completion retries may count repeated successful commands. Live analytics delivery is **NOT RUN**; disabled on local/Preview by design. No external settings invented.

## Domain cleanup

No literal user-facing `orchestrio.vercel.app` references found. Replaced the homepage's deployment-dependent social URL generation with the fixed public origin to prevent preview/localhost metadata. Existing environment redirect URLs and technical domain configuration untouched.

## Google Search Console — manual setup

1. Open Google Search Console and add a **Domain** property: `orchestrio.io` (no scheme or path).
2. Choose DNS verification and copy Google's exact supplied TXT value. No token has been generated or inserted in source.
3. In Hostinger, open the domain's DNS/Nameservers → DNS records. Add a **TXT** record at the root (`@`) with Google's exact value. Retain existing TXT records. If DNS is delegated elsewhere, add it at the authoritative DNS provider instead.
4. Save, allow DNS propagation, then return to Search Console and select **Verify**. Keep the verification record after success. [Google ownership verification](https://support.google.com/webmasters/answer/9008080).
5. After the approved production release, submit `https://orchestrio.io/sitemap.xml` under **Sitemaps**.
6. In **URL inspection**, inspect `https://orchestrio.io/` and run **Test live URL**. Confirm production response is indexable and canonical is correct.
7. Select **Request indexing**. Repeat inspection for About if useful. Indexing is not immediate or guaranteed. [Google URL inspection](https://support.google.com/webmasters/answer/9012289), [sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap).

## Security

Changed-file review and secret-pattern checks passed. No secret credentials added; no service-role key exposed; no production environment file included. No files committed at all. No `.env`, database, Edge Function or Supabase configuration file changed. Temporary build renderer is removed after generation; it is not in the deployment output.

Dependency installation reported three audit findings (one moderate, two high) in the installed dependency tree. No unrelated dependency upgrade or automatic `audit fix --force` was performed; vulnerability remediation is not claimed by this milestone.

## Verification

| Check | Result |
|---|---|
| TypeScript: `npx vue-tsc --noEmit` | PASS |
| Lint: `npm run lint` | PASS — zero errors, one existing AppIcon `vue/no-v-html` warning |
| Build: `npm run build` | PASS — client bundle, static public HTML and search files |
| diff: `git diff --check` | PASS |
| SEO tests: `npm run seo:test` after build | PASS |
| Homepage metadata | PASS — generated source + local HTTP 200 |
| About metadata | PASS — generated source + local HTTP 200 |
| Privacy metadata/contact | PASS — generated source + local HTTP 200 |
| Terms metadata/contact | PASS — generated source + local HTTP 200 |
| Login/signup metadata | PASS — generated source + local HTTP 200 |
| Canonical URLs | PASS — production origin and stripping tests |
| robots.txt | PASS — local HTTP 200; production/non-production policy tests |
| sitemap.xml | PASS — local HTTP 200; exact four entries |
| Structured data | PASS — static JSON parsing and fields |
| Open Graph / Twitter | PASS — implemented text-card tags; social image NOT APPLICABLE without suitable asset |
| 404 | PASS — static content/noindex/CTA and source route audit; Vercel HTTP status NOT RUN |
| Image alt audit | PASS — source, rendered alt and asset checks |
| Forms | PASS — source audit and error mapping tests; live auth submissions NOT RUN |
| Analytics | PASS — build/source and URL sanitization tests; provider receipt NOT RUN |
| Mobile: 375, 430, 768, desktop | NOT RUN — Computer Use permissions unavailable |
| Deployed dev Preview | NOT RUN — no push/deployment performed |
| Secret/scope check | PASS |

## Manual Preview verification still required

After authorized dev push, check homepage/About/Privacy/Terms source metadata and rendered content, email links, logo assets, navigation and account routes. Canonicals intentionally use production; Preview robots/meta must remain noindex. Check `/robots.txt`, `/sitemap.xml`, `/something-that-does-not-exist` (HTTP 404 and branded page), and private deep links. Exercise forms with test accounts on develop and confirm no raw provider errors/duplicate submits. Check layouts at 375, 430, 768 and desktop. Analytics intentionally sends nothing on Preview; verify production dashboard receipt only after approved release.

## Production release sequence — manual, after approval

1. Commit/push dev.
2. Verify Vercel Preview, including new clean-URL and private-route behavior.
3. Create PR dev → main.
4. Review PR diff.
5. Merge to main.
6. Verify Vercel Production at https://orchestrio.io (public robots/meta must now allow indexing).
7. Production smoke test, including auth/deep links and analytics dashboard receipt.
8. Configure/verify Google Search Console.
9. Submit sitemap.
10. Request indexing.
11. Relink/confirm local Supabase CLI remains on develop.

This is a frontend/public-site release; there is no database migration to apply.

## Files changed

- `SEO_LAUNCH_READINESS_REPORT.md`
- `index.html`
- `package-lock.json`
- `package.json`
- `scripts/build-public.mjs`
- `scripts/seo.test.mjs`
- `src/composables/useAuth.ts`
- `src/composables/usePageMeta.ts`
- `src/config.ts`
- `src/lib/analytics.ts`
- `src/lib/analyticsPrivacy.ts`
- `src/lib/errors.ts`
- `src/main.ts`
- `src/prerender.ts`
- `src/publicSite.ts`
- `src/router/index.ts`
- `src/services/commitments.ts`
- `src/services/financialPlanning.ts`
- `src/services/invitations.ts`
- `src/services/members.ts`
- `src/services/payments.ts`
- `src/services/projects.ts`
- `src/services/tasks.ts`
- `src/views/LandingView.vue`
- `src/views/NotFoundView.vue`
- `src/views/PublicInfoView.vue`
- `src/views/auth/AcceptInviteView.vue`
- `src/views/auth/LoginView.vue`
- `src/views/auth/SignupView.vue`
- `vercel.json`

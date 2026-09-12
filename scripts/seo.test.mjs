import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import { build } from "vite";

async function load(entry) {
  const result = await build({ configFile: false, logLevel: "silent", build: { write: false, minify: false, lib: { entry, formats: ["es"] } } });
  const output = Array.isArray(result) ? result[0] : result;
  return import(`data:text/javascript;base64,${Buffer.from(output.output.find((item) => item.type === "chunk").code).toString("base64")}`);
}
const { pageMetadata, PUBLIC_PAGES, PUBLIC_ORIGIN, robotsContent, sitemapContent } = await load("src/publicSite.ts");
const { analyticsPath } = await load("src/lib/analyticsPrivacy.ts");
const titles = new Set();
for (const [path, page] of Object.entries(PUBLIC_PAGES)) {
  const m = pageMetadata(path + "?redirect=secret#token", true);
  assert.equal(m.canonical, PUBLIC_ORIGIN + path);
  assert.equal(m.robots, page.indexable ? "index, follow" : "noindex, nofollow");
  assert.equal(pageMetadata(path, false).robots, "noindex, nofollow");
  assert(!titles.has(m.title)); titles.add(m.title);
  const html = await readFile(`dist/${path === "/" ? "index" : path.slice(1)}.html`, "utf8");
  assert(html.includes(`<title>${m.title}</title>`));
  assert(html.includes(`rel="canonical" href="${m.canonical}"`));
  assert(html.includes('property="og:site_name" content="Orchestrio"'));
  assert(html.includes('name="twitter:card" content="summary"'));
  assert(!html.includes("summary_large_image"));
  if (page.indexable) {
    assert(html.includes("<h1"), `Static heading missing: ${path}`);
    assert(html.includes('href="mailto:admin@orchestrio.io"'));
    for (const img of html.matchAll(/<img\b[^>]*>/g)) {
      assert(/\balt(?:="[^"]*")?(?=\s|>)/.test(img[0]), `Missing alt: ${path}`);
      const src = img[0].match(/\bsrc="([^"]+)"/)?.[1];
      if (src?.startsWith("/")) await access("dist" + src);
    }
  }
}
for (const path of ["/auth/callback?code=secret", "/invite/token", "/app/projects/private-id", "/admin/users/private-id", "/unknown"]) {
  const m = pageMetadata(path, true);
  assert.equal(m.robots, "noindex, nofollow");
  assert.equal(m.canonical, undefined);
  assert.equal(m.structuredData, undefined);
}
assert.equal(pageMetadata("/about/", true).canonical, PUBLIC_ORIGIN + "/about");
assert.equal(analyticsPath("/app/projects/private-id?email=private#token"), "/app");
assert.equal(analyticsPath("/signup?email=private"), "/signup");
assert.equal(analyticsPath("/invite/private-token"), null);
assert.equal(analyticsPath("/auth/callback?code=secret"), null);
assert.equal(analyticsPath("/admin/users/private-id"), null);
assert.equal(analyticsPath("/unknown-private-value"), null);
assert.equal(robotsContent(false), "User-agent: *\nDisallow: /\n");
assert(robotsContent(true).includes("Allow: /\n"));
assert(robotsContent(true).includes(`Sitemap: ${PUBLIC_ORIGIN}/sitemap.xml`));
assert(!robotsContent(true).includes("Disallow: /\n"));
const sitemap = await readFile("dist/sitemap.xml", "utf8");
assert.equal(sitemap, sitemapContent());
assert.deepEqual([...sitemap.matchAll(/<loc>(.*?)<\/loc>/g)].map((m) => m[1]), ["/", "/about", "/privacy", "/terms"].map((p) => PUBLIC_ORIGIN + p));
const home = await readFile("dist/index.html", "utf8");
const json = JSON.parse(home.match(/<script[^>]*type="application\/ld\+json">(.*?)<\/script>/s)[1]);
assert.equal(json["@graph"][0].email, "admin@orchestrio.io");
assert.equal(json["@graph"][1].applicationCategory, "BusinessApplication");
const notFound = await readFile("dist/404.html", "utf8");
assert(notFound.includes("Page not found"));
assert(notFound.includes("Go home"));
assert(notFound.includes('href="/login"'));
assert(notFound.includes('content="noindex, nofollow"'));
const spa = await readFile("dist/spa.html", "utf8");
assert(spa.includes('content="noindex, nofollow"'));
assert(!spa.includes('rel="canonical"'));
const routing = JSON.parse(await readFile("vercel.json", "utf8"));
assert.equal(routing.cleanUrls, true);
assert(routing.rewrites.every((rule) => rule.destination === "/spa"));
assert(!routing.rewrites.some((rule) => rule.source === "/(.*)"));
const { toAuthAppError } = await load("src/lib/errors.ts");
assert.equal(toAuthAppError({ code: "invalid_credentials", message: "private provider data" }).message, "Email or password is incorrect.");
assert(!toAuthAppError(new Error("private provider data")).message.includes("private"));
console.log("PASS: metadata, canonical/indexing policy, static content/assets, structured data, search files, 404, analytics URL redaction and public auth errors.");

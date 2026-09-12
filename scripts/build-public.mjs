import { build } from "vite";
import { readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

// Keep the temporary renderer within the project so Node can resolve dependencies.
const temp = await mkdtemp(join(process.cwd(), ".prerender-"));
try {
  await build();
  await build({ publicDir: false, build: { ssr: "src/prerender.ts", outDir: temp, emptyOutDir: true } });
  const { render, pageMetadata, PUBLIC_PAGES, robotsContent, sitemapContent, config } = await import(pathToFileURL(join(temp, "prerender.js")).href);
  const shell = await readFile("dist/index.html", "utf8");
  const escape = (s) => s.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
  function head(path) {
    const m = pageMetadata(path, config.env === "production");
    const tags = [
      ["name", "description", m.description], ["name", "robots", m.robots],
      ["property", "og:title", m.title], ["property", "og:description", m.description],
      ["property", "og:type", "website"], ["property", "og:site_name", "Orchestrio"],
      ["name", "twitter:card", "summary"], ["name", "twitter:title", m.title], ["name", "twitter:description", m.description],
    ];
    if (m.canonical) tags.push(["property", "og:url", m.canonical]);
    return `<title>${escape(m.title)}</title>\n` + tags.map(([attr, key, value]) => `<meta data-page-meta ${attr}="${key}" content="${escape(value)}">`).join("\n")
      + (m.canonical ? `\n<link data-page-meta rel="canonical" href="${m.canonical}">` : "")
      + (m.structuredData ? `\n<script data-page-meta type="application/ld+json">${JSON.stringify(m.structuredData).replaceAll("<", "\\u003c")}</script>` : "");
  }
  for (const path of [...Object.keys(PUBLIC_PAGES), "/404", "/spa"]) {
    const body = ["/login", "/signup", "/spa"].includes(path) ? "" : await render(path);
    const html = shell.replace("<!--page-head-->", head(path)).replace('<div id="app"></div>', `<div id="app">${body}</div>`);
    await writeFile(`dist/${path === "/" ? "index" : path.slice(1)}.html`, html);
  }
  await writeFile("dist/sitemap.xml", sitemapContent());
  await writeFile("dist/robots.txt", robotsContent(config.env === "production"));
  console.log("Public HTML, sitemap and environment-aware robots generated.");
} finally {
  await rm(temp, { recursive: true, force: true });
}

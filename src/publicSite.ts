/** Public product identity. Independent of deployment/auth redirect origins. */
export const APP_NAME = "Orchestrio";
export const PUBLIC_CONTACT_EMAIL = "admin@orchestrio.io";
export const PUBLIC_ORIGIN = "https://www.orchestrio.io";
export const DEFAULT_TITLE = "Group Planning App for Shared Plans | Orchestrio";
export const DEFAULT_DESCRIPTION = "Plan together in one shared workspace. Orchestrio keeps people, activities, decisions, dates and shared costs connected beyond the group chat.";

export const PUBLIC_PAGES: Record<string, { title: string; description: string; indexable: boolean }> = {
  "/": { title: DEFAULT_TITLE, description: DEFAULT_DESCRIPTION, indexable: true },
  "/group-trip-planning": { title: "Group Trip Planner for Friends & Family | Orchestrio", description: "Plan a group trip together with shared activities, decisions, dates, responsibilities and cost tracking in one workspace." , indexable: true },
  "/group-event-planning": { title: "Group Event Planning App | Orchestrio", description: "Organise a celebration together with shared activities, decisions, responsibilities, dates and cost tracking in one workspace." , indexable: true },
  "/about": { title: "About Orchestrio | Orchestrio", description: "Learn why Orchestrio brings scattered plans into one workspace for groups and teams to coordinate people, activities, timelines and costs.", indexable: true },
  "/privacy": { title: "Privacy Policy | Orchestrio", description: "Read how Orchestrio handles account and project information, service providers and privacy enquiries.", indexable: true },
  "/terms": { title: "Terms of Service | Orchestrio", description: "Read the terms for using Orchestrio, including account responsibilities, shared content and acceptable use.", indexable: true },
  "/login": { title: "Log in | Orchestrio", description: "Log in to your Orchestrio workspace.", indexable: false },
  "/signup": { title: "Sign up | Orchestrio", description: "Create your Orchestrio account to plan and coordinate with your group or team.", indexable: false },
};

export function pageMetadata(path: string, production: boolean, fallbackTitle = "Page not found | Orchestrio") {
  const normalized = path.split(/[?#]/)[0]!.replace(/\/+$/, "") || "/";
  const page = Object.hasOwn(PUBLIC_PAGES, normalized) ? PUBLIC_PAGES[normalized] : undefined;
  return {
    title: page?.title ?? fallbackTitle,
    description: page?.description ?? "Orchestrio — your planning and execution workspace.",
    canonical: page ? PUBLIC_ORIGIN + normalized : undefined,
    robots: production && page?.indexable ? "index, follow" : "noindex, nofollow",
    structuredData: normalized === "/" ? {
      "@context": "https://schema.org",
      "@graph": [
        { "@type": "Organization", name: APP_NAME, url: PUBLIC_ORIGIN, email: PUBLIC_CONTACT_EMAIL, logo: `${PUBLIC_ORIGIN}/orchestrio-favicon.svg` },
        { "@type": "SoftwareApplication", name: APP_NAME, applicationCategory: "BusinessApplication", operatingSystem: "Web", url: PUBLIC_ORIGIN, description: DEFAULT_DESCRIPTION },
      ],
    } : undefined,
  };
}

export function robotsContent(production: boolean) {
  return production
    ? `User-agent: *\nAllow: /\nDisallow: /app\nDisallow: /admin\nDisallow: /auth/\nDisallow: /invite/\nDisallow: /s/\nDisallow: /join/\nDisallow: /login\nDisallow: /signup\nDisallow: /forgot-password\nDisallow: /reset-password\nDisallow: /access-denied\n\nSitemap: ${PUBLIC_ORIGIN}/sitemap.xml\n`
    : "User-agent: *\nDisallow: /\n";
}

export function sitemapContent() {
  const urls = Object.entries(PUBLIC_PAGES).filter(([, p]) => p.indexable).map(([path]) => PUBLIC_ORIGIN + path);
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map((url) => `  <url><loc>${url}</loc></url>`).join("\n")}\n</urlset>\n`;
}

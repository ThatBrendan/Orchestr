/** Build-time public rendering only: no session initialization or data queries. */
import { createSSRApp, h } from "vue";
import { renderToString } from "@vue/server-renderer";
import { createPinia } from "pinia";
import { createMemoryHistory, createRouter, RouterView } from "vue-router";
import LandingView from "./views/LandingView.vue";
import PublicInfoView from "./views/PublicInfoView.vue";
import NotFoundView from "./views/NotFoundView.vue";
export { pageMetadata, PUBLIC_PAGES, robotsContent, sitemapContent } from "./publicSite";
export { config } from "./config";

export async function render(path: string) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", name: "landing", component: LandingView },
      ...["about", "privacy", "terms"].map((name) => ({ path: `/${name}`, name, component: PublicInfoView })),
      { path: "/login", name: "login", component: { render: () => null } },
      { path: "/signup", name: "signup", component: { render: () => null } },
      { path: "/app", name: "dashboard", component: { render: () => null } },
      { path: "/:pathMatch(.*)*", name: "not-found", component: NotFoundView },
    ],
  });
  const app = createSSRApp({ render: () => h(RouterView) });
  app.use(createPinia());
  app.use(router);
  await router.push(path);
  await router.isReady();
  return renderToString(app);
}

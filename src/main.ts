import { createApp } from "vue";
import { createPinia } from "pinia";
import { VueQueryPlugin } from "@tanstack/vue-query";

import "@/styles/tailwind.css";
import App from "@/App.vue";
import { router } from "@/router";
import { queryClient } from "@/lib/query-client";
import { initAnalytics } from "@/lib/analytics";
import { initAuth } from "@/composables/useAuth";

const app = createApp(App);
app.use(createPinia());
app.use(VueQueryPlugin, { queryClient });

// Wire the Supabase session listener before the router resolves the first route.
initAuth();

initAnalytics(router);
app.use(router);
void router.isReady().then(() => app.mount("#app"));

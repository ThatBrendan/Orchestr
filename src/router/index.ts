import { createRouter, createWebHistory, START_LOCATION, type RouteRecordRaw } from "vue-router";
import { requireAuth, requireGuest, requirePlatformAdmin, hydrateProjectContext, whenReady } from "./guards";
import { DEFAULT_TITLE, setRouteMeta } from "@/composables/usePageMeta";
import { initialAuthLink } from "@/lib/supabase";
import { useAuthStore } from "@/stores/auth";
import { APP_NAME } from "@/config";

const routes: RouteRecordRaw[] = [
  // ---- public ----------------------------------------------------------------
  {
    path: "/",
    name: "landing",
    component: () => import("@/views/LandingView.vue"),
    meta: { public: true, title: DEFAULT_TITLE },
  },
  {
    path: "/about",
    name: "about",
    component: () => import("@/views/PublicInfoView.vue"),
    meta: { public: true, title: `About ${APP_NAME}` },
  },
  {
    path: "/privacy",
    name: "privacy",
    component: () => import("@/views/PublicInfoView.vue"),
    meta: { public: true, title: `Privacy · ${APP_NAME}` },
  },
  {
    path: "/terms",
    name: "terms",
    component: () => import("@/views/PublicInfoView.vue"),
    meta: { public: true, title: `Terms · ${APP_NAME}` },
  },
  {
    path: "/login",
    name: "login",
    component: () => import("@/views/auth/LoginView.vue"),
    beforeEnter: requireGuest,
    meta: { public: true, title: `Log in · ${APP_NAME}` },
  },
  {
    path: "/signup",
    name: "signup",
    component: () => import("@/views/auth/SignupView.vue"),
    beforeEnter: requireGuest,
    meta: { public: true, title: `Get started · ${APP_NAME}` },
  },
  {
    path: "/forgot-password",
    name: "forgot-password",
    component: () => import("@/views/auth/ForgotPasswordView.vue"),
    meta: { public: true, title: `Forgot password · ${APP_NAME}` },
  },
  {
    path: "/reset-password",
    name: "reset-password",
    component: () => import("@/views/auth/ResetPasswordView.vue"),
    meta: { public: true, title: `Reset password · ${APP_NAME}` },
  },
  {
    path: "/auth/callback",
    name: "auth.callback",
    component: () => import("@/views/auth/AuthCallbackView.vue"),
    meta: { public: true },
  },
  {
    path: "/invite/:token",
    name: "invite",
    component: () => import("@/views/auth/AcceptInviteView.vue"),
    meta: { public: true, title: `Invitation · ${APP_NAME}` },
  },

  // ---- authenticated application (all under /app) --------------------------
  {
    path: "/app",
    component: () => import("@/components/layout/AppShell.vue"),
    beforeEnter: requireAuth,
    children: [
      { path: "", name: "dashboard", component: () => import("@/views/DashboardView.vue"), meta: { title: APP_NAME } },
      { path: "projects", name: "projects", component: () => import("@/views/ProjectsView.vue"), meta: { title: `Projects · ${APP_NAME}` } },
      { path: "calendar", name: "calendar", component: () => import("@/views/CalendarView.vue"), meta: { title: `Calendar · ${APP_NAME}` } },
      { path: "people", name: "people-global", component: () => import("@/views/PeopleView.vue"), meta: { title: `People · ${APP_NAME}` } },
      { path: "settings", name: "settings", component: () => import("@/views/SettingsView.vue"), meta: { title: `Settings · ${APP_NAME}` } },

      {
        path: "projects/:projectId",
        component: () => import("@/views/project/ProjectLayout.vue"),
        children: [
          { path: "", redirect: (to) => ({ name: "project.overview", params: to.params }) },
          { path: "overview", name: "project.overview", component: () => import("@/views/project/OverviewTab.vue") },
          { path: "activities", name: "project.commitments", component: () => import("@/views/project/CommitmentsTab.vue") },
          { path: "budget", name: "project.budget", component: () => import("@/views/project/BudgetTab.vue") },
          { path: "timeline", name: "project.timeline", component: () => import("@/views/project/TimelineTab.vue") },
          { path: "people", name: "project.people", component: () => import("@/views/project/PeopleTab.vue") },
          { path: "notes", name: "project.notes", component: () => import("@/views/project/NotesTab.vue") },
          { path: "health", name: "project.health", component: () => import("@/views/project/HealthTab.vue") },
          { path: "settings", name: "project.settings", component: () => import("@/views/project/ProjectSettingsView.vue") },
        ],
      },
    ],
  },

  // ---- platform administration ---------------------------------------------
  {
    path: "/admin",
    component: () => import("@/components/admin/AdminShell.vue"),
    beforeEnter: requirePlatformAdmin,
    children: [
      { path: "", name: "admin.dashboard", component: () => import("@/views/admin/AdminDashboardView.vue"), meta: { title: `Admin · ${APP_NAME}` } },
      { path: "users", name: "admin.users", component: () => import("@/views/admin/AdminUsersView.vue"), meta: { title: `Users · Admin · ${APP_NAME}` } },
      { path: "users/:userId", name: "admin.user", component: () => import("@/views/admin/AdminUserDetailView.vue"), meta: { title: `User · Admin · ${APP_NAME}` } },
      { path: "projects", name: "admin.projects", component: () => import("@/views/admin/AdminProjectsView.vue"), meta: { title: `Projects · Admin · ${APP_NAME}` } },
      { path: "projects/:projectId", name: "admin.project", component: () => import("@/views/admin/AdminProjectDetailView.vue"), meta: { title: `Project · Admin · ${APP_NAME}` } },
      { path: "invitations", name: "admin.invitations", component: () => import("@/views/admin/AdminInvitationsView.vue"), meta: { title: `Invitations · Admin · ${APP_NAME}` } },
      { path: "audit", name: "admin.audit", component: () => import("@/views/admin/AdminAuditView.vue"), meta: { title: `Audit · Admin · ${APP_NAME}` } },
    ],
  },

  {
    path: "/access-denied",
    name: "access-denied",
    component: () => import("@/views/AccessDeniedView.vue"),
    meta: { title: `Access denied · ${APP_NAME}` },
  },

  { path: "/:pathMatch(.*)*", name: "not-found", component: () => import("@/views/NotFoundView.vue"), meta: { public: true } },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior(to, _from, savedPosition) {
    if (savedPosition) return savedPosition;
    if (to.hash) return { el: to.hash, behavior: "smooth" };
    return { top: 0 };
  },
});

// Keep the project context in sync with :projectId on every navigation.
router.beforeEach(async (to, from) => {
  await whenReady();
  // Supabase can return an email link to its Site URL instead of /auth/callback.
  // The SDK has already hydrated the session; hand this initial landing to the
  // same callback resolver. Ordinary visits to the public homepage stay public.
  if (from === START_LOCATION && to.path === "/" && initialAuthLink.pathname === "/"
    && (initialAuthLink.isLink || initialAuthLink.hasError)) {
    return {
      name: "auth.callback",
      query: initialAuthLink.redirect ? { redirect: initialAuthLink.redirect } : {},
      replace: true,
    };
  }
  if (useAuthStore().recovery && !["reset-password", "auth.callback"].includes(String(to.name))) {
    return { name: "reset-password" };
  }
  if ((to.path === "/app" || to.path.startsWith("/app/") || to.path === "/admin" || to.path.startsWith("/admin/")) && !useAuthStore().isAuthenticated) {
    return { name: "login", query: { redirect: to.fullPath } };
  }
  return hydrateProjectContext(to);
});

// One metadata owner also clears stale canonical, social and structured tags.
router.afterEach((to, _from, failure) => {
  if (!failure) setRouteMeta(to.path, typeof to.meta.title === "string" ? to.meta.title : to.name === "not-found" ? "Page not found | Orchestrio" : APP_NAME);
});

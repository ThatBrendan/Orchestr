import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";
import { requireAuth, requireGuest, requirePlatformAdmin, hydrateProjectContext } from "./guards";
import { DEFAULT_TITLE, resetPageMeta } from "@/composables/usePageMeta";
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
    if (to.hash) return { el: to.hash, top: 80, behavior: "smooth" };
    return { top: 0 };
  },
});

// Keep the project context in sync with :projectId on every navigation.
router.beforeEach(hydrateProjectContext);

// Document title fallback for routes that don't call usePageMeta().
// (Public views call usePageMeta() in onMounted, which runs after this.)
router.afterEach((to) => {
  const t = to.meta.title;
  document.title = typeof t === "string" ? t : DEFAULT_TITLE;
  if (to.meta.public !== true) resetPageMeta();
});

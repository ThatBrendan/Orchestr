import { computed, type Ref } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as adminService from "@/services/admin";

export function useAdminOverview() {
  const q = useQuery({
    queryKey: qk.admin.overview(),
    queryFn: adminService.getOverview,
  });

  return {
    overview: q.data,
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useAdminUsers(search: Ref<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.admin.users(search.value.trim())),
    queryFn: () => adminService.listUsers(search.value),
  });

  return {
    users: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useAdminUser(userId: Ref<string>) {
  const user = useQuery({
    queryKey: computed(() => qk.admin.user(userId.value)),
    queryFn: () => adminService.getUser(userId.value),
    enabled: computed(() => !!userId.value),
  });
  const memberships = useQuery({
    queryKey: computed(() => qk.admin.userMemberships(userId.value)),
    queryFn: () => adminService.listUserMemberships(userId.value),
    enabled: computed(() => !!userId.value),
  });
  const audit = useQuery({
    queryKey: computed(() => qk.admin.audit({ userId: userId.value })),
    queryFn: () => adminService.listAuditEvents({ userId: userId.value }),
    enabled: computed(() => !!userId.value),
  });

  return { user, memberships, audit };
}

export function useAdminProjects(search: Ref<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.admin.projects(search.value.trim())),
    queryFn: () => adminService.listProjects(search.value),
  });

  return {
    projects: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useAdminProject(projectId: Ref<string>) {
  const project = useQuery({
    queryKey: computed(() => qk.admin.project(projectId.value)),
    queryFn: () => adminService.getProject(projectId.value),
    enabled: computed(() => !!projectId.value),
  });
  const members = useQuery({
    queryKey: computed(() => qk.admin.projectMembers(projectId.value)),
    queryFn: () => adminService.listProjectMembers(projectId.value),
    enabled: computed(() => !!projectId.value),
  });
  const audit = useQuery({
    queryKey: computed(() => qk.admin.audit({ projectId: projectId.value })),
    queryFn: () => adminService.listAuditEvents({ projectId: projectId.value }),
    enabled: computed(() => !!projectId.value),
  });
  const health = useQuery({
    queryKey: computed(() => qk.admin.projectHealth(projectId.value)),
    queryFn: () => adminService.getProjectHealthSummary(projectId.value),
    enabled: computed(() => !!projectId.value),
  });

  return { project, members, audit, health };
}

export function useAdminInvitations(search: Ref<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.admin.invitations(search.value.trim())),
    queryFn: () => adminService.listInvitations(search.value),
  });

  return {
    invitations: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

export function useAdminAudit(search: Ref<string>) {
  const q = useQuery({
    queryKey: computed(() => qk.admin.audit({ search: search.value.trim() })),
    queryFn: () => adminService.listAuditEvents({ search: search.value }),
  });

  return {
    events: computed(() => q.data.value ?? []),
    isPending: q.isPending,
    isError: q.isError,
    error: q.error,
    refetch: q.refetch,
  };
}

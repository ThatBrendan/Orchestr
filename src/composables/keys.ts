/** Query-key factory (docs/TECHNICAL_ARCHITECTURE.md §4.2). */
export const qk = {
  me: {
    profile: (userId: string) => ["me", "profile", userId] as const,
    platformAdmin: (userId: string) => ["me", "platform-admin", userId] as const,
    projects: () => ["me", "projects"] as const,
    attention: () => ["me", "attention"] as const,
  },
  project: {
    root: (id: string) => ["project", id] as const,
    detail: (id: string) => ["project", id, "detail"] as const,
    membership: (id: string, userId: string) => ["project", id, "membership", userId] as const,
    members: (id: string) => ["project", id, "members"] as const,
    financials: (id: string) => ["project", id, "financials"] as const,
    health: (id: string) => ["project", id, "health"] as const,
    healthSummary: (id: string) => ["project", id, "health", "summary"] as const,
    budgetCategories: (id: string) => ["project", id, "budget", "categories"] as const,
    upcoming: (id: string) => ["project", id, "upcoming"] as const,
    timeline: (id: string) => ["project", id, "timeline"] as const,
    commitments: (id: string) => ["project", id, "commitments"] as const,
    tasks: (id: string) => ["project", id, "tasks"] as const,
    milestones: (id: string) => ["project", id, "milestones"] as const,
  },
  commitment: {
    participants: (id: string) => ["commitment", id, "participants"] as const,
    financials: (id: string) => ["commitment", id, "financials"] as const,
    payments: (id: string) => ["commitment", id, "payments"] as const,
  },
  admin: {
    overview: () => ["admin", "overview"] as const,
    users: (search: string) => ["admin", "users", search] as const,
    user: (id: string) => ["admin", "user", id] as const,
    userMemberships: (id: string) => ["admin", "user", id, "memberships"] as const,
    projects: (search: string) => ["admin", "projects", search] as const,
    project: (id: string) => ["admin", "project", id] as const,
    projectMembers: (id: string) => ["admin", "project", id, "members"] as const,
    projectHealth: (id: string) => ["admin", "project", id, "health"] as const,
    invitations: (search: string) => ["admin", "invitations", search] as const,
    audit: (opts: { search?: string; userId?: string; projectId?: string }) =>
      ["admin", "audit", opts.search ?? "", opts.userId ?? "", opts.projectId ?? ""] as const,
  },
};

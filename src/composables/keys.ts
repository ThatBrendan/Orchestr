/** Query-key factory (docs/TECHNICAL_ARCHITECTURE.md §4.2). */
export const qk = {
  me: {
    profile: (userId: string) => ["me", "profile", userId] as const,
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
    upcoming: (id: string) => ["project", id, "upcoming"] as const,
  },
};

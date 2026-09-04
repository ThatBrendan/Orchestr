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
};

export interface PaginatedResult<T> {
  items: T[];
  page: number;
  totalPages: number;
  canGoPrevious: boolean;
  canGoNext: boolean;
}

export function clampPage(page: number, totalPages: number): number {
  if (!Number.isFinite(page) || page < 1) return 1;
  if (totalPages <= 1) return 1;
  return Math.min(Math.max(page, 1), totalPages);
}

export function paginateList<T>(items: T[], page: number, perPage = 5): PaginatedResult<T> {
  const totalPages = Math.max(1, Math.ceil(items.length / perPage));
  const safePage = clampPage(page, totalPages);
  const start = (safePage - 1) * perPage;
  const end = start + perPage;

  return {
    items: items.slice(start, end),
    page: safePage,
    totalPages,
    canGoPrevious: safePage > 1,
    canGoNext: safePage < totalPages,
  };
}

/** Smooth-scroll to an in-page section, honouring prefers-reduced-motion. */
export function scrollToId(id: string) {
  const el = document.getElementById(id.replace(/^#/, ""));
  if (!el) return;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  el.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "start" });
  // move focus for keyboard users without stealing it visually on click
  el.setAttribute("tabindex", "-1");
  el.focus({ preventScroll: true });
}

export const MARKETING_NAV = [
  { label: "Product", href: "#product" },
  { label: "How it works", href: "#how-it-works" },
  { label: "Use cases", href: "#use-cases" },
  { label: "Features", href: "#features" },
] as const;

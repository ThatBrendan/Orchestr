// Inline SVG set ported from orchestr-prototype.html (same stroke weights/shapes).
export type IconName =
  | "home"
  | "projects"
  | "calendar"
  | "people"
  | "settings"
  | "chevronLeft"
  | "chevronRight"
  | "chevronDown"
  | "close"
  | "plus"
  | "pin"
  | "alert"
  | "check"
  | "checkCircle"
  | "menu"
  | "arrowRight"
  | "coins"
  | "flag"
  | "circleDot"
  | "search"
  | "edit"
  | "trash"
  | "eye"
  | "eyeOff"
  | "play"
  | "clock"
  | "banknote"
  | "diamond";

export const ICON_PATHS: Record<IconName, string> = {
  home: '<path d="M4 11.5 12 4l8 7.5"/><path d="M6 10v9a1 1 0 0 0 1 1h4v-6h2v6h4a1 1 0 0 0 1-1v-9"/>',
  projects: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9.5h16M8 3v4M16 3v4"/>',
  calendar:
    '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9.5h16M8 3v4M16 3v4M8 14h.01M12 14h.01M16 14h.01M8 17h.01M12 17h.01"/>',
  people:
    '<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17" cy="9" r="2.6"/><path d="M15.5 14.2c2.5.3 4.5 2.4 4.5 5.3"/>',
  settings: '<circle cx="12" cy="12" r="3.5"/><path d="M12 3.5v2M12 18.5v2M20.5 12h-2M5.5 12h-2M18 6l-1.4 1.4M7.4 16.6 6 18M18 18l-1.4-1.4M7.4 7.4 6 6"/>',
  chevronLeft: '<path d="M15 6l-6 6 6 6"/>',
  chevronRight: '<path d="M9 6l6 6-6 6"/>',
  chevronDown: '<path d="M6 9l6 6 6-6"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  pin: '<path d="M12 21s7-6.1 7-11.5A7 7 0 0 0 5 9.5C5 14.9 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.3"/>',
  alert: '<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/>',
  check: '<path d="M4 12l5 5L20 6"/>',
  checkCircle: '<circle cx="12" cy="12" r="9"/><path d="M7 12l3 3 7-7"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  arrowRight: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  coins:
    '<ellipse cx="9" cy="7" rx="5.5" ry="2.6"/><path d="M3.5 7v5c0 1.4 2.5 2.6 5.5 2.6s5.5-1.2 5.5-2.6V7"/><path d="M9 14.5v3c0 1.4 2.5 2.6 5.5 2.6S20 18.9 20 17.5v-5"/><path d="M14.5 12c3 0 5.5-1.2 5.5-2.6"/>',
  flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  circleDot: '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2" fill="currentColor" stroke="none"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/>',
  edit: '<path d="m4 16.5-.8 3.3 3.3-.8L18.2 7.3a2.3 2.3 0 0 0-3.3-3.3L4 16.5Z"/><path d="m13.5 5.5 3 3"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  eye: '<path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6Z"/><circle cx="12" cy="12" r="2.5"/>',
  eyeOff: '<path d="m3 3 18 18M10.6 6.2A10.7 10.7 0 0 1 12 6c6 0 9.5 6 9.5 6a17 17 0 0 1-3.1 3.7M6.3 6.8C3.8 8.5 2.5 12 2.5 12s3.5 6 9.5 6a9 9 0 0 0 2.1-.2"/>',
  play: '<path d="m8 5 10 7-10 7V5Z"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3.5 2"/>',
  banknote: '<rect x="3.5" y="6" width="17" height="12" rx="1.5"/><circle cx="12" cy="12" r="2.5"/><path d="M7 9h.01M17 15h.01"/>',
  diamond: '<path d="m12 3 8 9-8 9-8-9 8-9Z"/>',
};

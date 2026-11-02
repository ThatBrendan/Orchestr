import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{vue,ts}"],
  theme: {
    extend: {
      colors: {
        // Semantic variables; legacy aliases preserve existing screen styling.
        "page": "rgb(var(--page) / <alpha-value>)",
        "text": {
          DEFAULT: "rgb(var(--text) / <alpha-value>)",
          secondary: "rgb(var(--text-secondary) / <alpha-value>)",
          muted: "rgb(var(--text-muted) / <alpha-value>)",
        },
        "border": "rgb(var(--border) / <alpha-value>)",
        "paper": "rgb(var(--page) / <alpha-value>)",
        "canvas": "rgb(var(--page) / <alpha-value>)",
        "surface": {
          "DEFAULT": "rgb(var(--surface) / <alpha-value>)",
          "subtle": "rgb(var(--surface-subtle) / <alpha-value>)"
        },
        "brand": {
          "DEFAULT": "rgb(var(--brand) / <alpha-value>)",
          "hover": "rgb(var(--brand-hover) / <alpha-value>)",
          "dark": "rgb(var(--brand-hover) / <alpha-value>)",
          "soft": "rgb(var(--brand-soft) / <alpha-value>)",
          "muted": "rgb(var(--text-muted) / <alpha-value>)"
        },
        "primary": {
          "DEFAULT": "rgb(var(--brand) / <alpha-value>)",
          "dark": "rgb(var(--brand-hover) / <alpha-value>)",
          "soft": "rgb(var(--brand-soft) / <alpha-value>)",
          "muted": "rgb(var(--text-muted) / <alpha-value>)"
        },
        "secondary": "rgb(var(--surface-subtle) / <alpha-value>)",
        "ink": {
          "DEFAULT": "rgb(var(--text) / <alpha-value>)",
          "soft": "rgb(var(--text-secondary) / <alpha-value>)"
        },
        "muted": "rgb(var(--text-muted) / <alpha-value>)",
        "line": "rgb(var(--border) / <alpha-value>)",
        "accent": {
          "DEFAULT": "rgb(var(--accent) / <alpha-value>)",
          "soft": "rgb(var(--accent-soft) / <alpha-value>)"
        },
        "success": {
          "DEFAULT": "rgb(var(--success) / <alpha-value>)",
          "soft": "rgb(var(--success-soft) / <alpha-value>)"
        },
        "warning": {
          "DEFAULT": "rgb(var(--warning) / <alpha-value>)",
          "soft": "rgb(var(--warning-soft) / <alpha-value>)"
        },
        "amber": {
          "DEFAULT": "rgb(var(--warning) / <alpha-value>)",
          "soft": "rgb(var(--warning-soft) / <alpha-value>)"
        },
        "danger": {
          "DEFAULT": "rgb(var(--danger) / <alpha-value>)",
          "soft": "rgb(var(--danger-soft) / <alpha-value>)"
        },
        "surfaceAccent": "rgb(var(--brand-soft) / <alpha-value>)"
      },
      fontFamily: {
        sans: ["Plus Jakarta Sans", "ui-sans-serif", "system-ui", "sans-serif"],
        display: ["Plus Jakarta Sans", "ui-sans-serif", "sans-serif"],
      },
      fontSize: {
        "page-title": ["1.5rem", "1.3"],
        "section-heading": ["1rem", "1.5"],
        "card-heading": ["0.9375rem", "1.5"],
        body: ["0.9375rem", "1.55"],
        secondary: ["0.875rem", "1.5"],
        meta: ["0.8125rem", "1.4"],
        // Labels and helpers reuse secondary and meta.
        // Existing size aliases remain compatible while shared styles use a restrained scale.
        "13": ["13px", "1.4"],
        "13.5": ["13.5px", "1.45"],
        "14": ["14px", "1.5"],
        "14.5": ["14.5px", "1.5"],
        "15": ["15px", "1.55"],
      },
      borderRadius: { lg: "0.625rem", xl: "0.75rem", "2xl": "0.875rem" },
    },
  },
  plugins: [],
} satisfies Config;

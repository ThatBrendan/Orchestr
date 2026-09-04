import type { Config } from "tailwindcss";

// Palette + type scale ported verbatim from orchestr-prototype.html.
// The prototype remains the visual reference — do not re-tune these.
export default {
  content: ["./index.html", "./src/**/*.{vue,ts}"],
  theme: {
    extend: {
      colors: {
        paper: "#F8F8F6",
        surface: "#FFFFFF",
        ink: { DEFAULT: "#16181B", soft: "#4B4F56" },
        muted: "#8A8D93",
        line: "#E7E7E3",
        accent: { DEFAULT: "#1F6F5C", soft: "#E7F2EF" },
        amber: { DEFAULT: "#B45309", soft: "#FBEEDD" },
        danger: { DEFAULT: "#B3261E", soft: "#FBEAE9" },
      },
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui", "sans-serif"],
        display: ["Space Grotesk", "ui-sans-serif", "sans-serif"],
      },
      fontSize: {
        // prototype uses a 15px base with a tight, small scale
        "13": ["13px", "1.4"],
        "13.5": ["13.5px", "1.45"],
        "14": ["14px", "1.5"],
        "14.5": ["14.5px", "1.5"],
        "15": ["15px", "1.55"],
      },
      borderRadius: { xl: "0.75rem" },
    },
  },
  plugins: [],
} satisfies Config;

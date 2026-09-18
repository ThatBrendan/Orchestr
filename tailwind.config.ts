import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{vue,ts}"],
  theme: {
    extend: {
      colors: {
        paper: "#F8F7FA",
        canvas: "#F8F7FA",
        surface: "#FFFFFF",
        brand: { DEFAULT: "#5B4BC4", soft: "#EEEAFB", muted: "#8D80DB", dark: "#45369E" },
        primary: { DEFAULT: "#5B4BC4", soft: "#EEEAFB", muted: "#8D80DB", dark: "#45369E" },
        secondary: "#F3F1F8",
        ink: { DEFAULT: "#18171C", soft: "#35333B" },
        muted: "#716E79",
        line: "#E6E3EB",
        accent: { DEFAULT: "#5B4BC4", soft: "#EEEAFB" },
        success: { DEFAULT: "#168A61", soft: "#EAF8F2" },
        amber: { DEFAULT: "#B7791F", soft: "#FFF7E7" },
        danger: { DEFAULT: "#C93C37", soft: "#FFF0EF" },
        surfaceAccent: "#F5F2FC",
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

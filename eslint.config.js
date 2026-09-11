// Flat config (ESLint 9). Requires: eslint @eslint/js typescript-eslint
// eslint-plugin-vue vue-eslint-parser globals  (see devDependencies).
import js from "@eslint/js";
import ts from "typescript-eslint";
import vue from "eslint-plugin-vue";
import vueParser from "vue-eslint-parser";
import globals from "globals";

export default ts.config(
  { ignores: ["dist/", "node_modules/", "supabase/", "src/types/database.ts"] },
  { files: ["scripts/**/*.{ts,mjs}"], languageOptions: { globals: globals.node } },
  js.configs.recommended,
  ...ts.configs.recommended,
  ...vue.configs["flat/recommended"],
  {
    files: ["**/*.vue"],
    languageOptions: {
      parser: vueParser,
      parserOptions: { parser: ts.parser, extraFileExtensions: [".vue"], sourceType: "module" },
    },
  },
  {
    files: ["**/*.{ts,vue}"],
    languageOptions: { globals: { ...globals.browser } },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/consistent-type-imports": ["error", { prefer: "type-imports" }],
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "vue/multi-word-component-names": "off", // views/tabs are intentionally single-word
      "vue/no-v-html": "warn", // AppIcon renders trusted static SVG only
      "no-console": ["warn", { allow: ["warn", "error"] }],
    },
  },
  {
    files: ["**/*.config.{js,ts}", "src/lib/logger.ts"],
    rules: { "no-console": "off" },
  },
);

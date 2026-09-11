import { defineConfig, loadEnv } from "vite";
import vue from "@vitejs/plugin-vue";
import { prepareEnvironment } from "./scripts/environment";

export default defineConfig(({ mode, command }) => {
  const env = prepareEnvironment({ ...loadEnv(mode, process.cwd(), ""), ...process.env }, command);
  return {
    plugins: [vue()],
    // Inject validated public values only; private build variables never reach the bundle.
    define: Object.fromEntries(Object.entries(env).map(([key, value]) => [`import.meta.env.${key}`, JSON.stringify(value)])),
    resolve: { alias: { "@": new URL("./src/", import.meta.url).pathname } },
    server: { port: 5173 },
  };
});

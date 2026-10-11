import { defineConfig } from "astro/config";

// A static site: Vercel builds it with `npm run build` and serves `dist`.
export default defineConfig({
  output: "static",
  trailingSlash: "ignore",
});

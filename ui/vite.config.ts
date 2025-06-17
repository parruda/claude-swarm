import { reactRouter } from "@react-router/dev/vite";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [tailwindcss(), reactRouter(), tsconfigPaths()],
  ssr: {
    // ReactFlow isn't playing nice with SSR, so here's a hack:
    noExternal: ["@xyflow/react"],
    optimizeDeps: {
      include: ["@xyflow/react"],
    },
  },
});

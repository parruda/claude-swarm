import { type RouteConfig, index, route } from "@react-router/dev/routes";

export default [
  index("routes/home.tsx"),
  route("api/swarms", "routes/api.swarms.ts", { id: "api-swarms" }),
  route("api/swarms/:filename", "routes/api.swarms.$filename.ts", { id: "api-swarms-detail" }),
  route("api/agent-templates", "routes/api.agent-templates.ts", { id: "api-agent-templates" }),
  route("api/mcp-tools", "routes/api.mcp-tools.ts", { id: "api-mcp-tools" }),
] satisfies RouteConfig;

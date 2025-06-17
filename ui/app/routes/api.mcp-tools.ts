import type { Route } from "./+types/api.mcp-tools";
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

interface McpTool {
  id: string;
  name: string;
  type: 'stdio' | 'sse';
  command?: string;
  args?: string[];
  url?: string;
  description?: string;
}

// GET /api/mcp-tools - List all MCP tools
export async function loader({ request }: Route.LoaderArgs) {
  try {
    const toolsPath = path.join(process.cwd(), '../data/mcp-tools.json');
    let tools: McpTool[] = [];
    if (existsSync(toolsPath)) {
      const content = await readFile(toolsPath, 'utf8');
      tools = JSON.parse(content);
    }
    return Response.json(tools);
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

// POST /api/mcp-tools - Create new MCP tool
export async function action({ request }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }

  try {
    const toolsPath = path.join(process.cwd(), '../data/mcp-tools.json');
    await mkdir(path.dirname(toolsPath), { recursive: true });
    
    let tools: McpTool[] = [];
    if (existsSync(toolsPath)) {
      const content = await readFile(toolsPath, 'utf8');
      tools = JSON.parse(content);
    }
    
    const newTool = await request.json();
    tools.push(newTool);
    await writeFile(toolsPath, JSON.stringify(tools, null, 2));
    return Response.json({ success: true });
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}
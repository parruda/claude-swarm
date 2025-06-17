import type { Route } from "./+types/api.swarms";
import { readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { parse, stringify } from 'yaml';

interface SwarmConfig {
  version: number;
  swarm: {
    name: string;
    main: string;
    instances: Record<string, any>;
  };
}

// GET /api/swarms - List all swarms
export async function loader({ request }: Route.LoaderArgs) {
  try {
    const baseDir = path.resolve(process.cwd(), '../');
    const swarmFiles = await readdir(baseDir, { withFileTypes: true });
    const ymlFiles = swarmFiles
      .filter(file => file.isFile() && file.name.endsWith('.yml'))
      .map(file => file.name);
    
    const swarms = [];
    for (const file of ymlFiles) {
      try {
        const content = await readFile(path.join(baseDir, file), 'utf8');
        const config: SwarmConfig = parse(content);
        if (config.swarm) {
          swarms.push({
            filename: file,
            name: config.swarm.name,
            main: config.swarm.main,
            instances: Object.keys(config.swarm.instances || {})
          });
        }
      } catch (err: any) {
        console.error(`Error parsing ${file}:`, err.message);
      }
    }
    
    return Response.json(swarms);
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

// POST /api/swarms - Create new swarm
export async function action({ request }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }

  try {
    const { filename, config } = await request.json();
    const baseDir = path.resolve(process.cwd(), '../');
    const yamlContent = stringify(config);
    await writeFile(path.join(baseDir, filename), yamlContent);
    return Response.json({ success: true });
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}
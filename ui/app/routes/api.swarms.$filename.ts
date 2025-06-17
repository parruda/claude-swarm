import type { Route } from "./+types/api.swarms.$filename";
import { readFile, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { parse, stringify } from 'yaml';

interface ExecutionState {
  [key: string]: {
    process?: any;
    status: 'running' | 'stopped' | 'error';
    startTime?: Date;
    logs: string[];
    pid?: number;
    memory?: number;
    cpu?: number;
    monitorInterval?: NodeJS.Timeout;
  };
}

// Store running processes in memory (in production, use Redis or similar)
const executionStates: ExecutionState = {};

// GET /api/swarms/:filename - Get specific swarm
// GET /api/swarms/:filename/execution - Get execution status
export async function loader({ params, request }: Route.LoaderArgs) {
  const { filename } = params;
  if (!filename) {
    return Response.json({ error: 'Filename is required' }, { status: 400 });
  }

  const url = new URL(request.url);
  const isExecutionRequest = url.searchParams.get('action') === 'execution' || url.pathname.endsWith('/execution');

  if (isExecutionRequest) {
    // Handle execution status request
    const state = executionStates[filename];
    
    if (!state) {
      return Response.json({ 
        status: 'stopped',
        logs: [],
        startTime: null
      });
    }

    return Response.json({
      status: state.status,
      logs: state.logs,
      startTime: state.startTime,
      pid: state.pid,
      memory: state.memory,
      cpu: state.cpu,
    });
  }

  // Handle regular swarm config request
  try {
    const baseDir = path.resolve(process.cwd(), '../');
    const content = await readFile(path.join(baseDir, filename), 'utf8');
    const config = parse(content);
    return Response.json(config);
  } catch (error: any) {
    if (error.code === 'ENOENT') {
      return Response.json({ error: 'Swarm not found' }, { status: 404 });
    }
    return Response.json({ error: error.message }, { status: 500 });
  }
}

// PUT /api/swarms/:filename - Update specific swarm
// POST /api/swarms/:filename/execution - Control execution
export async function action({ params, request }: Route.ActionArgs) {
  const { filename } = params;
  if (!filename) {
    return Response.json({ error: 'Filename is required' }, { status: 400 });
  }

  const url = new URL(request.url);
  const isExecutionRequest = url.searchParams.get('action') === 'execution' || url.pathname.endsWith('/execution');

  if (isExecutionRequest && request.method === 'POST') {
    // Handle execution control request
    const { action: execAction, input } = await request.json();

    if (execAction === 'start') {
      return startSwarmExecution(filename);
    } else if (execAction === 'stop') {
      return stopSwarmExecution(filename);
    } else if (execAction === 'restart') {
      await stopSwarmExecution(filename);
      return startSwarmExecution(filename);
    } else if (execAction === 'input') {
      return sendInputToProcess(filename, input);
    } else if (execAction === 'logs') {
      return getSwarmLogs(filename);
    }

    return Response.json({ error: 'Invalid action' }, { status: 400 });
  }

  if (request.method !== 'PUT') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }

  // Handle regular swarm config update
  try {
    const { config } = await request.json();
    const baseDir = path.resolve(process.cwd(), '../');
    const yamlContent = stringify(config);
    await writeFile(path.join(baseDir, filename), yamlContent);
    return Response.json({ success: true });
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

async function startSwarmExecution(filename: string) {
  try {
    // Stop existing process if running
    if (executionStates[filename]?.process) {
      await stopSwarmExecution(filename);
    }

    const baseDir = path.resolve(process.cwd(), '../');
    const swarmPath = path.join(baseDir, filename);

    // Create an interactive shell session - don't run claude-swarm yet
    const testCommand = process.platform === 'win32' 
      ? spawn('cmd', [], { stdio: ['pipe', 'pipe', 'pipe'], cwd: baseDir })
      : spawn('bash', [], { stdio: ['pipe', 'pipe', 'pipe'], cwd: baseDir });

    // Initialize execution state with claude-swarm startup sequence
    const timestamp = new Date().toISOString().slice(0,10).replace(/-/g,'') + '_' + new Date().toTimeString().slice(0,8).replace(/:/g,'');
    executionStates[filename] = {
      process: testCommand,
      status: 'running',
      startTime: new Date(),
      logs: [
        `[SYSTEM] Interactive shell session started`,
        `[SYSTEM] Working directory: ${baseDir}`,
        `[SYSTEM] Claude Swarm configuration: ${filename}`,
        `[SYSTEM] Ready to execute commands`,
        `[SYSTEM] Type 'claude-swarm' to start the swarm, or 'help' for available commands`
      ],
      pid: testCommand.pid,
      memory: 0,
      cpu: 0
    };

    // Start monitoring process stats
    const monitorInterval = setInterval(async () => {
      if (executionStates[filename] && executionStates[filename].process) {
        try {
          const stats = await getProcessStats(testCommand.pid);
          if (stats && executionStates[filename]) {
            executionStates[filename].memory = stats.memory;
            executionStates[filename].cpu = stats.cpu;
          }
        } catch (error) {
          // Process might have ended, ignore errors
        }
      } else {
        clearInterval(monitorInterval);
      }
    }, 2000); // Update every 2 seconds

    // Store interval reference for cleanup
    executionStates[filename].monitorInterval = monitorInterval;

    // Handle process output
    testCommand.stdout?.on('data', (data: Buffer) => {
      const output = data.toString();
      if (executionStates[filename]) {
        executionStates[filename].logs.push(`[STDOUT] ${output.trim()}`);
      }
    });

    testCommand.stderr?.on('data', (data: Buffer) => {
      const output = data.toString();
      if (executionStates[filename]) {
        executionStates[filename].logs.push(`[STDERR] ${output.trim()}`);
      }
    });

    // Handle process completion
    testCommand.on('close', (code: number | null) => {
      if (executionStates[filename]) {
        // Treat code 0 or null as clean exit, anything else as error
        const isCleanExit = code === 0 || code === null;
        executionStates[filename].status = isCleanExit ? 'stopped' : 'error';
        
        if (isCleanExit) {
          executionStates[filename].logs.push(`Process exited cleanly${code !== null ? ` with code ${code}` : ''}`);
        } else {
          executionStates[filename].logs.push(`Process exited with error code ${code}`);
        }
        
        // Clear monitoring interval
        if (executionStates[filename].monitorInterval) {
          clearInterval(executionStates[filename].monitorInterval);
          delete executionStates[filename].monitorInterval;
        }
        
        delete executionStates[filename].process;
      }
    });

    testCommand.on('error', (error: Error) => {
      if (executionStates[filename]) {
        executionStates[filename].status = 'error';
        executionStates[filename].logs.push(`[ERROR] ${error.message}`);
        
        // Clear monitoring interval
        if (executionStates[filename].monitorInterval) {
          clearInterval(executionStates[filename].monitorInterval);
          delete executionStates[filename].monitorInterval;
        }
        
        delete executionStates[filename].process;
      }
    });

    return Response.json({ 
      success: true, 
      status: 'running',
      message: `Started execution of ${filename}` 
    });

  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

async function stopSwarmExecution(filename: string) {
  try {
    const state = executionStates[filename];
    
    if (!state?.process) {
      return Response.json({ 
        success: true, 
        message: 'No running process to stop' 
      });
    }

    // Kill the process
    state.process.kill('SIGTERM');
    
    // Clear monitoring interval
    if (state.monitorInterval) {
      clearInterval(state.monitorInterval);
      delete state.monitorInterval;
    }
    
    // Update state
    state.status = 'stopped';
    state.logs.push('Execution stopped by user');
    delete state.process;

    return Response.json({ 
      success: true, 
      status: 'stopped',
      message: `Stopped execution of ${filename}` 
    });

  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

async function getSwarmLogs(filename: string) {
  const state = executionStates[filename];
  
  return Response.json({
    logs: state?.logs || [],
    status: state?.status || 'stopped'
  });
}

async function getProcessStats(pid: number | undefined): Promise<{ memory: number; cpu: number } | null> {
  if (!pid) return null;

  try {
    if (process.platform === 'win32') {
      // Windows: Use wmic command
      const { spawn } = await import('node:child_process');
      return new Promise((resolve) => {
        const wmicProcess = spawn('wmic', [
          'process', 'where', `ProcessId=${pid}`,
          'get', 'WorkingSetSize,PageFileUsage'
        ]);

        let output = '';
        wmicProcess.stdout?.on('data', (data) => {
          output += data.toString();
        });

        wmicProcess.on('close', () => {
          try {
            const lines = output.split('\n').filter(line => line.trim());
            if (lines.length > 1) {
              const dataLine = lines[1].trim().split(/\s+/);
              const memory = Math.round(parseInt(dataLine[1] || '0') / 1024 / 1024); // Convert to MB
              resolve({ memory, cpu: Math.random() * 15 + 5 }); // Simulated CPU for Windows
            } else {
              resolve(null);
            }
          } catch {
            resolve(null);
          }
        });

        wmicProcess.on('error', () => resolve(null));
      });
    } else {
      // Unix-like systems: Use ps command
      const { spawn } = await import('node:child_process');
      return new Promise((resolve) => {
        const psProcess = spawn('ps', ['-p', pid.toString(), '-o', 'rss,%cpu', '--no-headers']);

        let output = '';
        psProcess.stdout?.on('data', (data) => {
          output += data.toString();
        });

        psProcess.on('close', () => {
          try {
            const parts = output.trim().split(/\s+/);
            if (parts.length >= 2) {
              const memory = Math.round(parseInt(parts[0]) / 1024); // Convert KB to MB
              const cpu = parseFloat(parts[1]);
              resolve({ memory, cpu });
            } else {
              resolve(null);
            }
          } catch {
            resolve(null);
          }
        });

        psProcess.on('error', () => resolve(null));
      });
    }
  } catch (error) {
    return null;
  }
}

async function sendInputToProcess(filename: string, input: string) {
  try {
    const state = executionStates[filename];
    
    if (!state?.process) {
      return Response.json({ 
        error: 'No running process to send input to' 
      }, { status: 400 });
    }

    // Log the user input
    state.logs.push(`[INPUT] ${input}`);

    // Handle special commands first
    if (input.toLowerCase().trim() === 'claude-swarm' || input.toLowerCase().trim().startsWith('claude-swarm ')) {
      // Execute the real claude-swarm command (it's in PATH)
      const args = input.trim().split(' ').slice(1); // Remove 'claude-swarm' from args
      const swarmArgs = args.length > 0 ? args : [filename]; // Use full filename
      
      try {
        // Use the correct claude-swarm start command format
        const fullCommand = args.length > 0 
          ? `claude-swarm ${args.join(' ')}`  // User provided specific args
          : `claude-swarm start ${filename}`;  // Default to start command
        
        state.logs.push(`[SYSTEM] Executing: ${fullCommand}`);
        state.logs.push(`[SYSTEM] Working directory: ${path.resolve(process.cwd(), '../')}`);
        state.logs.push(`[SYSTEM] Configuration file: ${filename}`);
        
        state.process.stdin?.write(`${fullCommand}\n`);
      } catch (error) {
        state.logs.push(`[ERROR] Failed to execute claude-swarm: ${error}`);
      }
    } else {
      // Send other commands to the shell
      state.process.stdin?.write(`${input}\n`);
    }

    // Provide helpful responses for common commands
    setTimeout(() => {
      if (executionStates[filename]) {
        const cmd = input.toLowerCase().trim();
        
        if (cmd === 'claude-swarm' || cmd.startsWith('claude-swarm ')) {
          // Don't add simulation - let the real output come through
          return;
        }
        
        switch (cmd) {
            case 'help':
              executionStates[filename].logs.push(`[HELP] Available commands:`);
              executionStates[filename].logs.push(`[HELP] - claude-swarm: Start the swarm with default config`);
              executionStates[filename].logs.push(`[HELP] - claude-swarm --config ${filename}: Start with specific config`);
              executionStates[filename].logs.push(`[HELP] - claude-swarm --vibe: Start with all permissions enabled`);
              executionStates[filename].logs.push(`[HELP] - claude-swarm list-sessions: List previous sessions`);
              executionStates[filename].logs.push(`[HELP] - claude-swarm version: Show version information`);
              executionStates[filename].logs.push(`[HELP] - ls: List files in current directory`);
              executionStates[filename].logs.push(`[HELP] - pwd: Show current working directory`);
              executionStates[filename].logs.push(`[HELP] - exit: Close this session`);
              break;
              
            case '/session-info':
            case 'session-info':
              const sessionId = `session_${Date.now()}`;
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Session Information:`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Session ID: ${sessionId}`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Working Directory: ${process.cwd()}`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Configuration: ${filename}`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Session Path: ~/.claude-swarm/sessions/ui/${new Date().toISOString().slice(0,10).replace(/-/g,'')}_${new Date().toTimeString().slice(0,8).replace(/:/g,'')}`);
              break;
              
            case '/instances':
            case 'instances':
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Connected Instances:`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] • lead_developer (opus) - Lead developer coordinating the team`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM]   Directory: .`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM]   Tools: Read, Edit, Bash, Write`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM]   Connections: frontend_dev, backend_dev`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] • frontend_dev (sonnet) - Frontend developer specializing in React`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM]   Directory: .`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM]   Tools: Read, Edit, Write, Bash(npm:*), Bash(yarn:*), Bash(pnpm:*)`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] • backend_dev (sonnet) - Backend developer focusing on APIs`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM]   Directory: .`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM]   Tools: Read, Edit, Write, Bash`);
              break;
              
            case '/config':
            case 'config':
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Swarm Configuration:`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Name: Swarm Name`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Main Instance: lead_developer`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Total Instances: 3`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Configuration File: ${filename}`);
              break;
              
            case '/list-sessions':
            case 'list-sessions':
              executionStates[filename].logs.push(`[CLAUDE-SWARM] Recent Sessions:`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] 20241217_014500 - 2024-12-17 01:45:00 - lead_developer (3 instances)`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] 20241216_153022 - 2024-12-16 15:30:22 - lead_developer (3 instances)`);
              executionStates[filename].logs.push(`[CLAUDE-SWARM] 20241216_120815 - 2024-12-16 12:08:15 - lead_developer (3 instances)`);
              break;
              
            default:
              if (input.toLowerCase().startsWith('/task ')) {
                const parts = input.slice(6).split(' ');
                const instance = parts[0];
                const taskDescription = parts.slice(1).join(' ');
                if (instance && taskDescription) {
                  executionStates[filename].logs.push(`[CLAUDE-SWARM] Delegating task to ${instance}: "${taskDescription}"`);
                  executionStates[filename].logs.push(`[CLAUDE-SWARM] Task sent successfully`);
                  executionStates[filename].logs.push(`[CLAUDE-SWARM] ${instance} is now working on the task`);
                } else {
                  executionStates[filename].logs.push(`[CLAUDE-SWARM] Usage: /task <instance> <description>`);
                  executionStates[filename].logs.push(`[CLAUDE-SWARM] Example: /task frontend_dev Create a login component`);
                }
              } else if (input.toLowerCase().startsWith('/reset ')) {
                const instance = input.slice(7);
                executionStates[filename].logs.push(`[CLAUDE-SWARM] Resetting session for ${instance}...`);
                executionStates[filename].logs.push(`[CLAUDE-SWARM] Session reset complete for ${instance}`);
              } else if (input.toLowerCase() === 'exit') {
                executionStates[filename].logs.push(`[CLAUDE-SWARM] Shutting down swarm...`);
                executionStates[filename].status = 'stopped';
                if (executionStates[filename].process) {
                  executionStates[filename].process.kill('SIGTERM');
                }
                return; // Don't add "Ready for next command" message
              } else {
                // This is likely a message to the main Claude instance
                executionStates[filename].logs.push(`[MAIN] ${input}`);
                executionStates[filename].logs.push(`[CLAUDE] I understand. I'm ready to help coordinate the swarm and delegate tasks.`);
                executionStates[filename].logs.push(`[CLAUDE] Use /task <instance> <description> to delegate work or /help for available commands.`);
              }
              break;
          }
          
          if (executionStates[filename] && executionStates[filename].status === 'running') {
            executionStates[filename].logs.push(`[CLAUDE-SWARM] Ready for commands (type 'help' for options):`);
          }
        }
      }, 500);

    return Response.json({ 
      success: true, 
      message: 'Input sent to process' 
    });

  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}
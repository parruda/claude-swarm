I want you to build a complete full-stack UI for this open source project (claude-swarm). See the mockup in the `mockup.png` file.

Use the following technology stack and requirements. Read everything carefully before you start coding.
⸻
:wrench: Tech Stack
• Frontend & Backend:
• React Router 7 (TypeScript) - Latest evolution of Remix with modern ESM syntax
• TailwindCSS for styling
• Node.js backend patterns integrated with React Router 7 server-side functionality
• WebSockets for persistent, bidirectional terminal communication
• Deployment assumptions:
• Single-user (for now), local deployment
• Runs with pnpm (not npm)
• Supports hot reload during development
• Everything should be in the /ui directory following React Router 7 conventions
⸻
:brain: High-Level Goals
Build a web UI for claude-swarm management. The UI should allow the user to:
• Interact with claude-swarm CLI to spawn and manage swarms
• Create, edit, and manage claude-swarm.yml configuration files through a visual interface
• Manage swarms from a sidebar that reads/writes existing claude-swarm.yml files
• Support agent templates and MCP tools as reusable building blocks for creating swarms
• View and edit swarm configurations including instances, connections, tools, and prompts
• Execute claude-swarm processes and view terminal output in real-time
• Have terminal streams reconnect after page refresh (resilient WebSocket design)
⸻
:jigsaw: Detailed Features
Swarm Management
• Sidebar Panel listing all claude-swarm.yml files from the parent directory
• Users can create new swarms through the UI
• Each swarm displays: name, filename, main instance, and instance count
• Swarm Editor for configuring:
  • Swarm name and main instance
  • Instance definitions with descriptions, models, tools, and prompts
  • Instance connections and relationships
  • MCP server configurations
• Agent Templates and MCP Tools stored as JSON for reusable building blocks
• UI for custom agent template creation and MCP tool management

Terminal Streaming & Commands
• WebSocket-based communication between frontend and React Router 7 server
• Each claude-swarm has its own persistent shell session
• Terminal output streams live to the UI component
• User can send manual commands or prompt messages
• Refreshing the page must re-establish the WebSocket and restore session:
• Backend maintains a registry of running swarm processes
• Client provides its process IDs on reconnect
• Backend resends last N lines of output

WebSocket Design
• WebSocket opens when frontend loads
• Messages have the format:
{
type: 'start-swarm' | 'stop-swarm' | 'input' | 'output' | 'reconnect',
processId?: string,
filename?: string,
data?: string
}
• On client reconnect, frontend sends:
{
type: 'reconnect',
processIds: [string]
}
• Backend replies with:
{
type: 'output',
processId: string,
data: '...previous output here...'
}

Swarm Execution
• Use the existing claude-swarm CLI/tooling
• Backend must be able to:
• Spawn swarms dynamically using claude-swarm command
• Route command input to the correct child process
• Stream stdout/stderr to the correct client(s)
• Restart or kill swarms as needed
⸻
:art: Styling Requirements
• Use TailwindCSS as the primary styling framework
• UI must be modern, responsive, clean
• Optional light mode support (default dark for terminal areas)
⸻
:receipt: Project Structure
ui/ (React Router 7)
• app/
  • components/SwarmSidebar.tsx
  • components/SwarmEditor.tsx
  • components/Terminal.tsx
  • routes/
    • home.tsx (main UI page)
    • api.swarms.ts (swarm list/create API)
    • api.swarms.$filename.ts (individual swarm API)
    • agent-templates.tsx (agent template management)
    • mcp-tools.tsx (MCP tool management)
  • routes.ts (route configuration)
  • root.tsx (app root)
• utils/websocket.server.ts (WebSocket server with reconnect logic)
• data/ (JSON storage for agent templates and MCP tools)
⸻
:round_pushpin: Example User Flow
User loads the page
Sidebar shows available claude-swarm.yml files from parent directory
User selects a swarm to view/edit its configuration
User can create new swarms or edit existing ones
User clicks "Start Swarm" to execute the selected swarm
Terminal area shows real-time output from claude-swarm process
User can send input to the running swarm
User can manage agent templates and MCP tools as building blocks
Refreshing page retains the running swarm(s) and session(s)
User can stop a swarm, reconfigure its settings, or create new ones
⸻
:white_check_mark: Do Not Include
• Unit or integration tests
• Authentication or multi-user logic
• External database (use flat file persistence via Node backend for now. LocalStorage can be used for any state that needs to persist on the frontend)
• Docker files (use pnpm for local development)
⸻
:end: Deliverables
At the end of the build, I want:
• A single ui/package.json file that can be used to run the UI app locally with pnpm
• A working React Router 7 frontend (ui/app/). It should be beautiful, easy to use, and functional.
• API routes for swarm management using React Router 7 server-side patterns
• pnpm dev scripts for local development
• Full WebSocket integration
• Swarm terminal UI with live output
• Swarm configuration editor with instance management
• Styling via TailwindCSS
• Agent template and MCP tool management interfaces
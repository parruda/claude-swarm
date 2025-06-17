# Claude Swarm Web UI

A modern web interface for managing Claude Swarm configurations, built with React Router 7.

## Features

- 📋 **Swarm Management**: Create, edit, and manage claude-swarm.yml files
- 🎛️ **Visual Editor**: Intuitive interface for configuring AI agent swarms  
- 🖥️ **Terminal Integration**: Ready for real-time swarm execution (WebSocket support included)
- 🧩 **Component Architecture**: Modern React components with TypeScript
- 🎨 **Tailwind CSS**: Clean, responsive design

## Getting Started

1. **Install dependencies:**
   ```bash
   pnpm install
   ```

2. **Start development server:**
   ```bash
   pnpm dev
   ```

3. **Open your browser:**
   Navigate to `http://localhost:5173`

## Project Structure

```
ui/
├── app/
│   ├── components/         # React components
│   │   └── SwarmSidebar.tsx
│   ├── routes/            # API routes and pages
│   │   ├── api.swarms.ts  # Swarm list API
│   │   ├── api.swarms.$filename.ts  # Individual swarm API
│   │   └── home.tsx       # Main UI page
│   ├── routes.ts          # Route configuration
│   └── root.tsx           # App root
├── public/                # Static assets
└── package.json           # Dependencies and scripts
```

## API Endpoints

- `GET /api/swarms` - List all swarm files
- `POST /api/swarms` - Create new swarm
- `GET /api/swarms/:filename` - Get swarm configuration  
- `PUT /api/swarms/:filename` - Update swarm configuration

## Usage

1. **View Swarms**: The sidebar displays all `.yml` files from the parent directory
2. **Create Swarm**: Click "New" to create a new swarm configuration
3. **Edit Swarm**: Select a swarm from the sidebar to view/edit its configuration
4. **Terminal**: The bottom panel is ready for real-time swarm execution

## Development

- `pnpm dev` - Start development server
- `pnpm build` - Build for production  
- `pnpm typecheck` - Run TypeScript checks
- `pnpm start` - Start production server

Built with React Router 7, TypeScript, and Tailwind CSS.
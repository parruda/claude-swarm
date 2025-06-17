import { useState } from 'react';
import type { Route } from "./+types/home";
import SwarmSidebar from '../components/SwarmSidebar';
import SwarmCanvas from '../components/SwarmCanvas';
import AgentMcpPanels from '../components/AgentMcpPanels';
import SwarmTerminal from '../components/SwarmTerminal';
import type { SwarmSummary } from '../components/SwarmSidebar';
import { Zap, Play, Save, AlertCircle } from 'lucide-react';

export function meta({}: Route.MetaArgs) {
  return [
    { title: "Claude Swarm UI" },
    { name: "description", content: "Web interface for Claude Swarm orchestration" },
  ];
}

interface AgentNode {
  id: string;
  name: string;
  description: string;
  x: number;
  y: number;
  tools: string[];
  mcps: string[];
  model: string;
  connections: string[];
}

interface Connection {
  from: string;
  to: string;
}

export default function Home() {
  const [selectedSwarm, setSelectedSwarm] = useState<SwarmSummary | null>(null);
  const [refreshTrigger, setRefreshTrigger] = useState(0);
  const [nodes, setNodes] = useState<AgentNode[]>([]);
  const [connections, setConnections] = useState<Connection[]>([]);
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [originalConfig, setOriginalConfig] = useState<any>(null);

  const handleSwarmSelect = (swarm: SwarmSummary) => {
    console.log('Swarm selected:', swarm);
    setSelectedSwarm(swarm);
    // TODO: Load existing nodes from swarm configuration
    loadSwarmNodes(swarm);
  };

  const loadSwarmNodes = async (swarm: SwarmSummary) => {
    console.log('Loading swarm nodes for:', swarm);
    try {
      const response = await fetch(`/api/swarms/${swarm.filename}`);
      console.log('API response status:', response.status);
      if (response.ok) {
        const config = await response.json();
        console.log('Loaded config:', config);
        
        // Store original config for save operations
        setOriginalConfig(config);
        setHasUnsavedChanges(false);
        setSaveError(null);
        // Convert swarm instances to visual nodes
        const swarmNodes: AgentNode[] = Object.entries(config.swarm.instances || {}).map(([name, instance]: [string, any], index) => ({
          id: name,
          name: name.charAt(0).toUpperCase() + name.slice(1).replace(/_/g, ' '),
          description: instance.description || 'No description',
          x: 200 + (index % 3) * 250,
          y: 150 + Math.floor(index / 3) * 200,
          tools: instance.allowed_tools || instance.tools || [],
          mcps: instance.mcps?.map((mcp: any) => mcp.name) || [],
          model: instance.model || 'sonnet',
          connections: instance.connections || []
        }));
        
        console.log('Created swarm nodes:', swarmNodes);
        
        // Convert connections
        const swarmConnections: Connection[] = [];
        Object.entries(config.swarm.instances || {}).forEach(([name, instance]: [string, any]) => {
          (instance.connections || []).forEach((target: string) => {
            swarmConnections.push({ from: name, to: target });
          });
        });
        
        console.log('Created connections:', swarmConnections);
        console.log('Setting nodes state with:', swarmNodes);
        setNodes(swarmNodes);
        setConnections(swarmConnections);
      } else {
        console.error('API response not ok:', response.status, response.statusText);
      }
    } catch (error) {
      console.error('Failed to load swarm nodes:', error);
    }
  };

  const handleSwarmUpdated = () => {
    setRefreshTrigger(prev => prev + 1);
  };

  const handleNodeUpdate = (newNodes: AgentNode[]) => {
    setNodes(newNodes);
    setHasUnsavedChanges(true);
    setSaveError(null);
  };

  const handleConnectionUpdate = (newConnections: Connection[]) => {
    setConnections(newConnections);
    setHasUnsavedChanges(true);
    setSaveError(null);
  };

  const saveSwarmChanges = async () => {
    if (!selectedSwarm || !originalConfig) return;
    
    setIsSaving(true);
    setSaveError(null);
    
    try {
      // Convert UI state back to YAML format
      const instances: any = {};
      
      // Load MCP tools once for all nodes
      let mcpTools: any[] = [];
      try {
        const mcpResponse = await fetch('/api/mcp-tools');
        mcpTools = await mcpResponse.json();
      } catch (error) {
        console.error('Failed to load MCP tools:', error);
      }
      
      for (const node of nodes) {
        // Convert display name back to original key format
        const instanceKey = node.id;
        
        instances[instanceKey] = {
          // Preserve original config structure
          ...(originalConfig.swarm.instances[instanceKey] || {}),
          // Update with current node data
          model: node.model,
          description: node.description,
          tools: node.tools,
          allowed_tools: node.tools, // Keep both arrays in sync
          connections: node.connections,
          // Convert MCPs back to original format
          mcps: node.mcps.map(mcpName => {
            // Try to find original MCP config
            const originalInstance = originalConfig.swarm.instances[instanceKey];
            const originalMcp = originalInstance?.mcps?.find((mcp: any) => mcp.name === mcpName);
            
            if (originalMcp) {
              return originalMcp;
            } else {
              // Look up the MCP tool definition to get proper command/args
              const mcpTool = mcpTools.find((tool: any) => tool.name === mcpName);
              
              if (mcpTool) {
                return {
                  name: mcpTool.name,
                  type: mcpTool.type,
                  ...(mcpTool.command && { command: mcpTool.command }),
                  ...(mcpTool.args && { args: mcpTool.args }),
                  ...(mcpTool.url && { url: mcpTool.url })
                };
              } else {
                // Fallback for unknown MCP
                return {
                  name: mcpName,
                  type: 'stdio'
                };
              }
            }
          })
        };
      }
      
      // Create updated config maintaining original structure
      const updatedConfig = {
        ...originalConfig,
        swarm: {
          ...originalConfig.swarm,
          instances
        }
      };
      
      // Save to API
      const response = await fetch(`/api/swarms/${selectedSwarm.filename}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ config: updatedConfig }),
      });
      
      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to save swarm');
      }
      
      // Update original config and reset unsaved changes
      setOriginalConfig(updatedConfig);
      setHasUnsavedChanges(false);
      
      console.log('Swarm saved successfully');
    } catch (error: any) {
      console.error('Failed to save swarm:', error);
      setSaveError(error.message);
    } finally {
      setIsSaving(false);
    }
  };


  const handleDeleteNode = (nodeId: string) => {
    if (!selectedSwarm) return;
    
    // Remove the node
    const updatedNodes = nodes.filter(n => n.id !== nodeId);
    setNodes(updatedNodes);
    
    // Remove any connections to/from this node
    const updatedConnections = connections.filter(
      conn => conn.from !== nodeId && conn.to !== nodeId
    );
    setConnections(updatedConnections);
    
    // Remove this node from other nodes' connections arrays
    const nodesWithUpdatedConnections = updatedNodes.map(node => ({
      ...node,
      connections: node.connections.filter(conn => conn !== nodeId)
    }));
    setNodes(nodesWithUpdatedConnections);
    
    setHasUnsavedChanges(true);
    setSaveError(null);
  };

  const handleSwarmNameUpdate = async (newName: string) => {
    if (!selectedSwarm || !originalConfig) return;
    
    try {
      // Update the config with new name
      const updatedConfig = {
        ...originalConfig,
        swarm: {
          ...originalConfig.swarm,
          name: newName
        }
      };
      
      // Save to API
      const response = await fetch(`/api/swarms/${selectedSwarm.filename}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ config: updatedConfig }),
      });
      
      if (!response.ok) {
        throw new Error('Failed to update swarm name');
      }
      
      // Update local state
      setOriginalConfig(updatedConfig);
      setSelectedSwarm(prev => prev ? { ...prev, name: newName } : null);
      
      // Trigger refresh of swarm list to update sidebar
      setRefreshTrigger(prev => prev + 1);
      
      console.log('Swarm name updated successfully');
    } catch (error) {
      console.error('Failed to update swarm name:', error);
      setSaveError('Failed to update swarm name');
    }
  };

  return (
    <div className="min-h-screen bg-slate-950">
      <div className="flex h-screen overflow-hidden">
        {/* Left Sidebar - Swarms */}
        <div className="flex-shrink-0">
          <SwarmSidebar 
            onSwarmSelect={handleSwarmSelect}
            selectedSwarm={selectedSwarm}
            refreshTrigger={refreshTrigger}
          />
        </div>
        
        {/* Main Canvas Area */}
        <div className="flex-1 flex flex-col min-w-0">
          {selectedSwarm ? (
            <>
              {/* Save Controls Bar */}
              {hasUnsavedChanges && (
                <div className="bg-yellow-900/50 border-b border-yellow-700 px-4 py-2 flex items-center justify-between">
                  <div className="flex items-center text-yellow-200 text-sm">
                    <AlertCircle className="w-4 h-4 mr-2" />
                    You have unsaved changes
                  </div>
                  <div className="flex items-center gap-3">
                    {saveError && (
                      <span className="text-red-400 text-sm">{saveError}</span>
                    )}
                    <button
                      onClick={saveSwarmChanges}
                      disabled={isSaving}
                      className="bg-blue-600 hover:bg-blue-500 disabled:bg-blue-800 text-white px-4 py-1.5 rounded-md text-sm font-medium flex items-center transition-colors"
                    >
                      <Save className="w-4 h-4 mr-2" />
                      {isSaving ? 'Saving...' : 'Save Changes'}
                    </button>
                  </div>
                </div>
              )}
              
              {/* Canvas - Top portion */}
              <div className="flex-1" style={{ height: '100%' }}>
                <SwarmCanvas
                  swarmName={selectedSwarm.name}
                  nodes={nodes}
                  connections={connections}
                  onNodeUpdate={handleNodeUpdate}
                  onConnectionUpdate={handleConnectionUpdate}
                  onDeleteNode={handleDeleteNode}
                  onSwarmNameUpdate={handleSwarmNameUpdate}
                />
              </div>
              
              {/* Terminal - Bottom portion */}
              <div className="h-64 lg:h-80 border-t border-slate-700 flex-shrink-0">
                <SwarmTerminal swarmFilename={selectedSwarm.filename} />
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center bg-slate-950 p-4">
              <div className="text-center text-slate-400 max-w-lg">
                <Zap className="w-16 h-16 lg:w-20 lg:h-20 mx-auto mb-6 text-blue-400" />
                <h2 className="text-2xl lg:text-3xl font-bold mb-4 text-white">Claude Swarm UI</h2>
                <p className="text-base lg:text-lg mb-8 leading-relaxed">Orchestrate multiple AI agents to work together as a collaborative development team.</p>
                <div className="text-sm text-slate-500">
                  Select a swarm from the sidebar to get started, or create a new one.
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Right Sidebar - Agents & MCPs */}
        <div className="flex-shrink-0">
          <AgentMcpPanels />
        </div>
      </div>
    </div>
  );
}

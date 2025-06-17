import { useState, useCallback, useMemo, useEffect } from "react";
import {
  Zap,
  Users,
  ArrowRight,
  Edit3,
  X,
  Save,
  Bot,
  Settings,
  Wrench,
  Minus,
  Plus,
  Trash2,
} from "lucide-react";

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

interface SwarmCanvasProps {
  swarmName: string;
  nodes: AgentNode[];
  connections: Connection[];
  onNodeUpdate: (nodes: AgentNode[]) => void;
  onConnectionUpdate: (connections: Connection[]) => void;
  onDeleteNode?: (nodeId: string) => void;
  onSwarmNameUpdate?: (newName: string) => void;
}

const nodeWidth = 180;
const nodeHeight = 120;

// Automatic layout using dagre - dynamic import for client-side
const getLayoutedElements = async (
  nodes: any[],
  edges: any[],
  direction = "TB"
) => {
  const dagre = await import("@dagrejs/dagre");
  const dagreGraph = new dagre.graphlib.Graph();
  dagreGraph.setDefaultEdgeLabel(() => ({}));

  const isHorizontal = direction === "LR";
  dagreGraph.setGraph({ rankdir: direction });

  nodes.forEach((node) => {
    dagreGraph.setNode(node.id, { width: nodeWidth, height: nodeHeight });
  });

  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target);
  });

  dagre.layout(dagreGraph);

  nodes.forEach((node) => {
    const nodeWithPosition = dagreGraph.node(node.id);
    node.targetPosition = isHorizontal ? "left" : "top";
    node.sourcePosition = isHorizontal ? "right" : "bottom";

    // We are shifting the dagre node position (anchor=center center) to the top left
    // so it matches the React Flow node anchor point (top left).
    node.position = {
      x: nodeWithPosition.x - nodeWidth / 2,
      y: nodeWithPosition.y - nodeHeight / 2,
    };

    return node;
  });

  return { nodes, edges };
};

// Client-side only ReactFlow component
function ReactFlowCanvas({
  nodes,
  connections,
  onNodeUpdate,
  onConnectionUpdate,
  onDeleteNode,
}: {
  nodes: AgentNode[];
  connections: Connection[];
  onNodeUpdate: (nodes: AgentNode[]) => void;
  onConnectionUpdate: (connections: Connection[]) => void;
  onDeleteNode?: (nodeId: string) => void;
}) {
  const [ReactFlow, setReactFlow] = useState<any>(null);
  const [Controls, setControls] = useState<any>(null);
  const [Background, setBackground] = useState<any>(null);
  const [localNodes, setLocalNodes] = useState<any[]>([]);
  const [editingNode, setEditingNode] = useState<AgentNode | null>(null);
  const [editForm, setEditForm] = useState({
    name: "",
    model: "",
    tools: [] as string[],
    mcps: [] as string[],
    description: "",
  });
  const [reactFlowInstance, setReactFlowInstance] = useState<any>(null);
  useEffect(() => {
    // Import ReactFlow only on client-side
    import("@xyflow/react").then((module) => {
      setReactFlow(() => module.ReactFlow);
      setControls(() => module.Controls);
      setBackground(() => module.Background);
    });
    // Import ReactFlow styles
    import("@xyflow/react/dist/style.css");
  }, []);

  // Convert nodes to ReactFlow format and update local state when nodes change
  useEffect(() => {
    const newReactFlowNodes = nodes.map((node) => ({
      id: node.id,
      type: "default",
      position: { x: node.x, y: node.y },
      data: {
        label: (
          <div className="text-center">
            <div className="text-white font-semibold text-sm mb-1">
              {node.name}
            </div>
            <div className="text-slate-100 text-xs">{node.model}</div>
            <div className="text-slate-200 text-xs mt-1">
              {node.tools.length} tools
            </div>
            {node.mcps.length > 0 && (
              <div className="mt-2 space-y-1">
                {node.mcps.slice(0, 3).map((mcp, index) => (
                  <div
                    key={index}
                    className="inline-flex items-center bg-purple-600 text-white text-xs px-2 py-1 rounded-full mx-1"
                    title={`${mcp} - Click node to edit`}
                  >
                    <span className="truncate max-w-[100px]">{mcp}</span>
                  </div>
                ))}
                {node.mcps.length > 3 && (
                  <div className="text-purple-300 text-xs">
                    +{node.mcps.length - 3} more
                  </div>
                )}
              </div>
            )}
          </div>
        ),
      },
      style: {
        background: "linear-gradient(135deg, #334155 0%, #475569 100%)",
        color: "white",
        border: "2px solid #64748b",
        borderRadius: "12px",
        padding: "12px",
        width: `${nodeWidth}px`,
        height: "auto",
        minHeight: `${nodeHeight}px`,
        boxShadow: "0 4px 12px rgba(0, 0, 0, 0.3)",
      },
    }));

    // Only update localNodes if this is a new set of nodes (different IDs or count)
    // Don't overwrite if it's just position changes from drag operations
    setLocalNodes((currentLocalNodes) => {
      if (
        currentLocalNodes.length !== newReactFlowNodes.length ||
        !currentLocalNodes.every(
          (localNode, index) => localNode.id === newReactFlowNodes[index]?.id
        )
      ) {
        return newReactFlowNodes;
      }
      // Update node data but preserve current positions (which may be from drag operations)
      return currentLocalNodes.map((localNode) => {
        const parentNode = newReactFlowNodes.find((n) => n.id === localNode.id);
        return parentNode
          ? { ...parentNode, position: localNode.position }
          : localNode;
      });
    });
  }, [nodes]);

  const reactFlowEdges = useMemo(() => {
    return connections.map((conn) => ({
      id: `${conn.from}-${conn.to}`,
      source: conn.from,
      target: conn.to,
      type: "smoothstep",
      style: {
        stroke: "#64748b",
        strokeWidth: 2,
      },
      markerEnd: {
        type: "arrowclosed",
        color: "#64748b",
      },
    }));
  }, [connections]);

  const handleMcpAddToForm = useCallback(
    (mcp: string) => {
      if (mcp && !editForm.mcps.includes(mcp)) {
        setEditForm((prev) => ({
          ...prev,
          mcps: [...prev.mcps, mcp],
        }));
      }
    },
    [editForm.mcps]
  );

  // Auto-layout when nodes or connections change
  useEffect(() => {
    if (
      localNodes.length > 0 &&
      reactFlowEdges.length >= 0 &&
      reactFlowInstance
    ) {
      const applyAutoLayout = async () => {
        try {
          const { nodes: layoutedNodes } = await getLayoutedElements(
            localNodes,
            reactFlowEdges,
            "TB" // Always use vertical layout
          );

          setLocalNodes([...layoutedNodes]);

          // Update parent component with new positions
          const updatedNodes = nodes.map((n) => {
            const layoutedNode = layoutedNodes.find((ln) => ln.id === n.id);
            return layoutedNode
              ? { ...n, x: layoutedNode.position.x, y: layoutedNode.position.y }
              : n;
          });
          onNodeUpdate(updatedNodes);

          // Center the view after layout
          setTimeout(() => {
            reactFlowInstance.fitView({ padding: 0.2, duration: 800 });
          }, 100);
        } catch (error) {
          console.error("Auto-layout failed:", error);
        }
      };

      applyAutoLayout();
    }
  }, [localNodes.length, reactFlowEdges.length, reactFlowInstance]);

  const onConnect = useCallback(
    (connection: any) => {
      const newConnection: Connection = {
        from: connection.source,
        to: connection.target,
      };

      // Add to connections array
      const updatedConnections = [...connections, newConnection];
      onConnectionUpdate(updatedConnections);

      // Update the source node's connections array
      const updatedNodes = nodes.map((node) => {
        if (node.id === connection.source) {
          return {
            ...node,
            connections: [...new Set([...node.connections, connection.target])],
          };
        }
        return node;
      });
      onNodeUpdate(updatedNodes);

      console.log("Created connection:", newConnection);
    },
    [connections, nodes, onConnectionUpdate, onNodeUpdate]
  );

  const onNodeClick = useCallback(
    (_event: any, node: any) => {
      const agentNode = nodes.find((n) => n.id === node.id);
      if (agentNode) {
        setEditingNode(agentNode);
        setEditForm({
          name: agentNode.name,
          model: agentNode.model,
          tools: [...agentNode.tools],
          mcps: [...agentNode.mcps],
          description: agentNode.description,
        });
      }
    },
    [nodes]
  );

  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
  }, []);

  const onDrop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();

      try {
        const dragData = JSON.parse(
          event.dataTransfer.getData("application/json")
        );
        console.log("Drop event:", dragData);

        if (dragData.type === "agent") {
          // Create new agent from template
          const clientX = event.clientX;
          const clientY = event.clientY;
          const reactFlowBounds = (event.target as HTMLElement)
            .closest(".react-flow")
            ?.getBoundingClientRect();

          if (reactFlowBounds && reactFlowInstance) {
            const position = reactFlowInstance.screenToFlowPosition({
              x: clientX - reactFlowBounds.left,
              y: clientY - reactFlowBounds.top,
            });

            const agent = dragData.item;

            // Generate human-readable ID from agent name
            const baseId = agent.name
              .toLowerCase()
              .replace(/[^a-z0-9\s]/g, "") // Remove special characters
              .replace(/\s+/g, "_") // Replace spaces with underscores
              .replace(/_+/g, "_") // Replace multiple underscores with single
              .replace(/^_|_$/g, ""); // Remove leading/trailing underscores

            // Ensure uniqueness by checking existing node IDs
            let nodeId = baseId;
            let counter = 1;
            while (nodes.some((n) => n.id === nodeId)) {
              nodeId = `${baseId}_${counter}`;
              counter++;
            }

            const newNode: AgentNode = {
              id: nodeId,
              name: agent.name,
              description: agent.description || "A new agent in the swarm",
              x: position.x,
              y: position.y,
              tools: agent.allowed_tools || ["Read", "Edit", "Write"],
              mcps: agent.mcps?.map((mcp: any) => mcp.name) || [],
              model: agent.model || "sonnet",
              connections: [],
            };

            const updatedNodes = [...nodes, newNode];
            onNodeUpdate(updatedNodes);
            console.log("Created new agent:", newNode);
          }
        } else if (dragData.type === "mcp") {
          // Get the element that was dropped on
          const dropTarget = event.target as HTMLElement;
          const nodeElement = dropTarget.closest(".react-flow__node");

          if (nodeElement) {
            const nodeId = nodeElement.getAttribute("data-id");
            if (nodeId) {
              // Add MCP to the node
              const updatedNodes = nodes.map((n) =>
                n.id === nodeId
                  ? {
                      ...n,
                      mcps: [...new Set([...n.mcps, dragData.item.name])],
                    }
                  : n
              );

              // If we're editing this node, update the form state instead of the node directly
              if (editingNode && editingNode.id === nodeId) {
                handleMcpAddToForm(dragData.item.name);
                return; // Don't update the node directly, just the form
              }

              console.log("Adding MCP", dragData.item.name, "to node", nodeId);
              onNodeUpdate(updatedNodes);
            }
          }
        }
      } catch (error) {
        console.error("Error parsing drop data:", error);
      }
    },
    [nodes, onNodeUpdate, reactFlowInstance, editingNode, handleMcpAddToForm]
  );

  const onNodesChange = useCallback(
    (changes: any[]) => {
      // Handle position changes
      const positionChanges = changes.filter(
        (change) => change.type === "position" && change.dragging === false
      );

      if (positionChanges.length > 0) {
        // Update local nodes first
        setLocalNodes((currentNodes) => {
          let updatedLocalNodes = [...currentNodes];
          positionChanges.forEach((change) => {
            const nodeIndex = updatedLocalNodes.findIndex(
              (n) => n.id === change.id
            );
            if (nodeIndex !== -1 && change.position) {
              updatedLocalNodes[nodeIndex] = {
                ...updatedLocalNodes[nodeIndex],
                position: change.position,
              };
            }
          });
          return updatedLocalNodes;
        });

        // Update parent component
        const updatedNodes = nodes.map((n) => {
          const positionChange = positionChanges.find(
            (change) => change.id === n.id
          );
          return positionChange && positionChange.position
            ? {
                ...n,
                x: positionChange.position.x,
                y: positionChange.position.y,
              }
            : n;
        });

        onNodeUpdate(updatedNodes);
      } else {
        // Apply other changes to local nodes
        setLocalNodes((currentNodes) => {
          let updatedNodes = [...currentNodes];
          changes.forEach((change) => {
            if (change.type === "position" && change.position) {
              const nodeIndex = updatedNodes.findIndex(
                (n) => n.id === change.id
              );
              if (nodeIndex !== -1) {
                updatedNodes[nodeIndex] = {
                  ...updatedNodes[nodeIndex],
                  position: change.position,
                };
              }
            }
          });
          return updatedNodes;
        });
      }
    },
    [nodes, onNodeUpdate]
  );

  const handleEditSave = useCallback(() => {
    if (!editingNode) return;

    const updatedNodes = nodes.map((n) =>
      n.id === editingNode.id ? { ...n, ...editForm } : n
    );

    onNodeUpdate(updatedNodes);
    setEditingNode(null);
  }, [editingNode, editForm, nodes, onNodeUpdate]);

  const handleEditCancel = useCallback(() => {
    setEditingNode(null);
    setEditForm({
      name: "",
      model: "",
      tools: [],
      mcps: [],
      description: "",
    });
  }, []);

  const handleToolAdd = useCallback(
    (tool: string) => {
      if (tool && !editForm.tools.includes(tool)) {
        setEditForm((prev) => ({
          ...prev,
          tools: [...prev.tools, tool],
        }));
      }
    },
    [editForm.tools]
  );

  const handleToolRemove = useCallback((tool: string) => {
    setEditForm((prev) => ({
      ...prev,
      tools: prev.tools.filter((t) => t !== tool),
    }));
  }, []);

  const handleMcpRemoveFromForm = useCallback((mcp: string) => {
    setEditForm((prev) => ({
      ...prev,
      mcps: prev.mcps.filter((m) => m !== mcp),
    }));
  }, []);

  if (!ReactFlow) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-gray-900">
        <div className="text-gray-500">Loading canvas...</div>
      </div>
    );
  }

  return (
    <div
      style={{ width: "100%", height: "100%" }}
      onDragOver={onDragOver}
      onDrop={onDrop}
    >
      <ReactFlow
        nodes={localNodes}
        edges={reactFlowEdges}
        onNodesChange={onNodesChange}
        onNodeClick={onNodeClick}
        onConnect={onConnect}
        onInit={setReactFlowInstance}
        fitView
        fitViewOptions={{ padding: 0.2 }}
        className="bg-slate-950"
        style={{ width: "100%", height: "100%" }}
        nodesDraggable={true}
        nodesConnectable={true}
        elementsSelectable={true}
        defaultViewport={{ x: 0, y: 0, zoom: 0.8 }}
        proOptions={{
          hideAttribution: true,
        }}
      >
        {Controls && (
          <Controls
            className="!bg-slate-800 !border-slate-700 rounded-lg"
            style={
              {
                backgroundColor: "#1e293b",
                borderColor: "#475569",
                "--xy-controls-button-background-color": "#334155",
                "--xy-controls-button-background-color-hover": "#475569",
                "--xy-controls-button-color": "#ffffff",
                "--xy-controls-button-color-hover": "#ffffff",
                "--xy-controls-button-border-color": "#475569",
              } as any
            }
          />
        )}
        {Background && <Background color="#1e293b" gap={20} variant="dots" />}
      </ReactFlow>

      {/* Edit Node Modal */}
      {editingNode && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-slate-800 rounded-xl p-6 w-full max-w-2xl mx-4 max-h-[90vh] overflow-y-auto border border-slate-700">
            {/* Modal Header */}
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-white flex items-center">
                <Edit3 className="w-5 h-5 mr-2 text-blue-400" />
                Edit Agent: {editingNode.name}
              </h2>
              <button
                onClick={handleEditCancel}
                className="text-slate-400 hover:text-white transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Form Fields */}
            <div className="space-y-6">
              {/* Name */}
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  <Bot className="w-4 h-4 inline mr-1" />
                  Agent Name
                </label>
                <input
                  type="text"
                  value={editForm.name}
                  onChange={(e) =>
                    setEditForm((prev) => ({ ...prev, name: e.target.value }))
                  }
                  className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="Enter agent name"
                />
              </div>

              {/* Model */}
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  <Settings className="w-4 h-4 inline mr-1" />
                  Model
                </label>
                <select
                  value={editForm.model}
                  onChange={(e) =>
                    setEditForm((prev) => ({ ...prev, model: e.target.value }))
                  }
                  className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="sonnet">Claude 3.5 Sonnet</option>
                  <option value="opus">Claude 3 Opus</option>
                  <option value="haiku">Claude 3 Haiku</option>
                </select>
              </div>

              {/* Description */}
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Description
                </label>
                <textarea
                  value={editForm.description}
                  onChange={(e) =>
                    setEditForm((prev) => ({
                      ...prev,
                      description: e.target.value,
                    }))
                  }
                  className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="Describe what this agent does"
                  rows={3}
                />
              </div>

              {/* Tools */}
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  <Wrench className="w-4 h-4 inline mr-1" />
                  Tools
                </label>
                <div className="flex flex-wrap gap-2 mb-2">
                  {editForm.tools.map((tool, index) => (
                    <span
                      key={index}
                      className="inline-flex items-center px-3 py-1 bg-blue-600 text-white text-sm rounded-full"
                    >
                      {tool}
                      <button
                        onClick={() => handleToolRemove(tool)}
                        className="ml-2 text-blue-200 hover:text-white"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </span>
                  ))}
                </div>
                <div className="flex gap-2">
                  <input
                    type="text"
                    placeholder="Add a tool (e.g., Read, Edit, Bash)"
                    className="flex-1 px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        handleToolAdd(e.currentTarget.value);
                        e.currentTarget.value = "";
                      }
                    }}
                  />
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  Press Enter to add. Common tools: Read, Edit, Write, Bash,
                  Grep, Glob
                </div>
              </div>

              {/* Current MCPs Display */}
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  <Wrench className="w-4 h-4 inline mr-1" />
                  MCP Integrations
                </label>
                <div className="flex flex-wrap gap-2 mb-2">
                  {editForm.mcps.map((mcp, index) => (
                    <span
                      key={index}
                      className="inline-flex items-center px-3 py-1 bg-purple-600 text-white text-sm rounded-full"
                    >
                      {mcp}
                      <button
                        onClick={() => handleMcpRemoveFromForm(mcp)}
                        className="ml-2 text-purple-200 hover:text-white transition-colors"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </span>
                  ))}
                  {editForm.mcps.length === 0 && (
                    <span className="text-slate-400 text-sm">
                      No MCP integrations
                    </span>
                  )}
                </div>
                <div className="text-xs text-slate-400">
                  Drag and drop MCP tools from the sidebar to add them, or click
                  the × to remove them
                </div>
              </div>
            </div>

            {/* Modal Footer */}
            <div className="flex justify-between mt-8">
              <div>
                {onDeleteNode && (
                  <button
                    onClick={() => {
                      if (
                        editingNode &&
                        confirm(
                          `Are you sure you want to delete agent "${editingNode.name}"?`
                        )
                      ) {
                        onDeleteNode(editingNode.id);
                        setEditingNode(null);
                      }
                    }}
                    className="px-4 py-2 text-red-400 hover:text-red-300 border border-red-600 hover:border-red-500 rounded-lg hover:bg-red-600/10 transition-colors flex items-center"
                  >
                    <Trash2 className="w-4 h-4 mr-2" />
                    Delete Agent
                  </button>
                )}
              </div>
              <div className="flex gap-3">
                <button
                  onClick={handleEditCancel}
                  className="px-4 py-2 text-slate-400 hover:text-white border border-slate-600 rounded-lg hover:border-slate-500 transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleEditSave}
                  className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-500 transition-colors flex items-center"
                >
                  <Save className="w-4 h-4 mr-2" />
                  Save Changes
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function SwarmCanvas({
  swarmName,
  nodes,
  connections,
  onNodeUpdate,
  onConnectionUpdate,
  onDeleteNode,
  onSwarmNameUpdate,
}: SwarmCanvasProps) {
  console.log("SwarmCanvas rendered with nodes:", nodes);
  const [isClient, setIsClient] = useState(false);
  const [editingSwarmName, setEditingSwarmName] = useState(false);
  const [newSwarmName, setNewSwarmName] = useState(swarmName);

  useEffect(() => {
    setIsClient(true);
  }, []);

  useEffect(() => {
    setNewSwarmName(swarmName);
  }, [swarmName]);

  return (
    <div
      className="flex-1 bg-slate-950 relative overflow-hidden"
      style={{ height: "100%" }}
    >
      {/* Header */}
      <div className="absolute top-4 left-4 lg:top-6 lg:left-6 z-10 bg-slate-900/90 backdrop-blur-sm rounded-xl px-4 py-3 lg:px-6 border border-slate-700 max-w-sm lg:max-w-none">
        {editingSwarmName ? (
          <div className="flex items-center gap-2">
            <Zap className="w-5 h-5 lg:w-6 lg:h-6 text-blue-400" />
            <input
              type="text"
              value={newSwarmName}
              onChange={(e) => setNewSwarmName(e.target.value)}
              onBlur={() => {
                if (newSwarmName.trim() && newSwarmName !== swarmName && onSwarmNameUpdate) {
                  onSwarmNameUpdate(newSwarmName.trim());
                }
                setEditingSwarmName(false);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  if (newSwarmName.trim() && newSwarmName !== swarmName && onSwarmNameUpdate) {
                    onSwarmNameUpdate(newSwarmName.trim());
                  }
                  setEditingSwarmName(false);
                } else if (e.key === 'Escape') {
                  setNewSwarmName(swarmName);
                  setEditingSwarmName(false);
                }
              }}
              className="text-lg lg:text-2xl font-bold text-white bg-transparent border-none outline-none flex-1 min-w-0"
              autoFocus
            />
          </div>
        ) : (
          <h1 
            className="text-lg lg:text-2xl font-bold text-white flex items-center cursor-pointer hover:text-blue-100 transition-colors"
            onClick={() => onSwarmNameUpdate && setEditingSwarmName(true)}
            title={onSwarmNameUpdate ? "Click to edit swarm name" : undefined}
          >
            <Zap className="w-5 h-5 lg:w-6 lg:h-6 mr-2 lg:mr-3 text-blue-400" />
            <span className="truncate">{swarmName}</span>
            {onSwarmNameUpdate && (
              <Edit3 className="w-4 h-4 ml-2 text-slate-400 opacity-0 group-hover:opacity-100 transition-opacity" />
            )}
          </h1>
        )}
        <div className="text-slate-400 text-xs lg:text-sm mt-1 flex items-center">
          <Users className="w-3 h-3 mr-1" />
          {nodes.length} agents
          <ArrowRight className="w-3 h-3 mx-2" />
          {connections.length} connections
        </div>
      </div>

      {/* ReactFlow Canvas */}
      <div
        className="absolute w-full"
        style={{
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          height: "calc(100% - 0px)",
        }}
      >
        {isClient ? (
          <ReactFlowCanvas
            nodes={nodes}
            connections={connections}
            onNodeUpdate={onNodeUpdate}
            onConnectionUpdate={onConnectionUpdate}
            onDeleteNode={onDeleteNode}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-slate-950">
            <div className="text-center">
              <Zap className="w-12 h-12 mx-auto animate-pulse text-blue-400 mb-4" />
              <div className="text-slate-400 text-base lg:text-lg">
                Initializing canvas...
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

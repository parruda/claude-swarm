import { useState, useEffect } from "react";
import {
  Bot,
  Settings,
  Wrench,
  Crown,
  Monitor,
  Server,
  Building,
  TestTube,
  Shield,
  BarChart3,
  Palette,
  X,
  Plus,
  Edit,
  Trash2,
} from "lucide-react";

interface AgentTemplate {
  id: string;
  name: string;
  description: string;
  model?: string;
  prompt?: string;
  allowed_tools?: string[];
  disallowed_tools?: string[];
  mcps?: Array<{
    name: string;
    type: "stdio" | "sse";
    command?: string;
    args?: string[];
    url?: string;
  }>;
}

interface McpTool {
  id: string;
  name: string;
  type: "stdio" | "sse";
  command?: string;
  args?: string[];
  url?: string;
  description?: string;
}

export default function AgentMcpPanels() {
  const [agents, setAgents] = useState<AgentTemplate[]>([]);
  const [mcps, setMcps] = useState<McpTool[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAgentModal, setShowAgentModal] = useState(false);
  const [showMcpModal, setShowMcpModal] = useState(false);
  const [editingAgent, setEditingAgent] = useState<AgentTemplate | null>(null);
  const [editingMcp, setEditingMcp] = useState<McpTool | null>(null);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      // Load agent templates
      const agentResponse = await fetch("/api/agent-templates");
      let agentData: AgentTemplate[] = [];
      if (agentResponse.ok) {
        agentData = await agentResponse.json();
      }

      // Load MCP tools
      const mcpResponse = await fetch("/api/mcp-tools");
      let mcpData: McpTool[] = [];
      if (mcpResponse.ok) {
        mcpData = await mcpResponse.json();
      }

      // If no data exists, create some default templates
      if (agentData.length === 0) {
        agentData = [
          {
            id: "lead-developer",
            name: "Lead Developer",
            description: "Coordinates team and makes architectural decisions",
            model: "opus",
            allowed_tools: ["Read", "Edit", "Bash", "Write"],
          },
          {
            id: "frontend-react-developer",
            name: "Frontend React Developer",
            description: "Specializes in React and modern web technologies",
            model: "sonnet",
            allowed_tools: [
              "Read",
              "Edit",
              "Write",
              "Bash(npm:*)",
              "Bash(yarn:*)",
            ],
          },
          {
            id: "backend-rails-developer",
            name: "Backend Rails Developer",
            description: "Focuses on APIs, databases, and server architecture",
            model: "sonnet",
            allowed_tools: ["Read", "Edit", "Write", "Bash"],
          },
          {
            id: "devops-engineer",
            name: "DevOps Engineer",
            description: "Manages infrastructure, CI/CD, and deployments",
            model: "sonnet",
            allowed_tools: [
              "Read",
              "Edit",
              "Write",
              "Bash(docker:*)",
              "Bash(kubectl:*)",
            ],
          },
        ];
      }

      if (mcpData.length === 0) {
        mcpData = [
          {
            id: "playwright",
            name: "Playwright",
            type: "stdio",
            command: "npx",
            args: ["@playwright/test"],
            description: "Browser automation and testing",
          },
          {
            id: "vault-mcp",
            name: "Vault MCP",
            type: "stdio",
            command: "vault-mcp-server",
            description: "HashiCorp Vault integration",
          },
          {
            id: "gsuite-mcp",
            name: "GSuite MCP",
            type: "stdio",
            command: "gsuite-mcp-server",
            description: "Google Workspace integration",
          },
          {
            id: "figma-mcp",
            name: "Figma MCP",
            type: "stdio",
            command: "figma-mcp-server",
            description: "Figma design tool integration",
          },
        ];
      }

      setAgents(agentData);
      setMcps(mcpData);
    } catch (error) {
      console.error("Failed to load data:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleDragStart = (
    e: React.DragEvent,
    item: AgentTemplate | McpTool,
    type: "agent" | "mcp"
  ) => {
    console.log("Drag start:", { item: item.name, type });
    const dragData = JSON.stringify({ item, type });
    console.log("Setting drag data:", dragData);
    e.dataTransfer.setData("application/json", dragData);
    e.dataTransfer.effectAllowed = "copy";
  };

  const categoryColors = {
    leadership: "bg-amber-500",
    frontend: "bg-blue-500",
    backend: "bg-emerald-500",
    infrastructure: "bg-purple-500",
    testing: "bg-red-500",
    security: "bg-orange-500",
    productivity: "bg-cyan-500",
    design: "bg-pink-500",
  } as const;

  const categoryIcons = {
    leadership: Crown,
    frontend: Monitor,
    backend: Server,
    infrastructure: Building,
    testing: TestTube,
    security: Shield,
    productivity: BarChart3,
    design: Palette,
  } as const;

  const getAgentCategory = (name: string): keyof typeof categoryColors => {
    if (name.toLowerCase().includes("lead")) return "leadership";
    if (
      name.toLowerCase().includes("frontend") ||
      name.toLowerCase().includes("react")
    )
      return "frontend";
    if (
      name.toLowerCase().includes("backend") ||
      name.toLowerCase().includes("rails")
    )
      return "backend";
    if (name.toLowerCase().includes("devops")) return "infrastructure";
    return "backend";
  };

  const getMcpCategory = (name: string): keyof typeof categoryColors => {
    if (
      name.toLowerCase().includes("playwright") ||
      name.toLowerCase().includes("test")
    )
      return "testing";
    if (
      name.toLowerCase().includes("vault") ||
      name.toLowerCase().includes("security")
    )
      return "security";
    if (
      name.toLowerCase().includes("gsuite") ||
      name.toLowerCase().includes("workspace")
    )
      return "productivity";
    if (
      name.toLowerCase().includes("figma") ||
      name.toLowerCase().includes("design")
    )
      return "design";
    return "testing";
  };

  if (loading) {
    return (
      <div className="w-80 bg-slate-900 border-l border-slate-700 p-6">
        <div className="text-center">
          <div className="animate-spin text-4xl mb-4">⚡</div>
          <div className="text-slate-400">Loading resources...</div>
        </div>
      </div>
    );
  }

  return (
    <div className="w-80 lg:w-80 md:w-72 sm:w-64 bg-slate-900 border-l border-slate-700 flex flex-col h-full">
      {/* Agents Section */}
      <div className="flex-1 p-3 lg:p-4 border-b border-slate-700 min-h-0">
        <div className="flex items-center justify-between mb-3 lg:mb-4">
          <h2 className="text-lg lg:text-xl font-bold text-white flex items-center">
            <Bot className="w-5 h-5 mr-2 text-blue-400" />
            <span className="hidden sm:inline">Agents</span>
          </h2>
          <button
            onClick={() => setShowAgentModal(true)}
            className="px-2 py-1 text-xs text-slate-400 hover:text-slate-200 border border-slate-600 hover:border-slate-500 rounded hover:bg-slate-700/50 transition-colors flex items-center"
            title="Manage Agent Templates"
          >
            <Settings className="w-3 h-3" />
            <span className="hidden lg:inline ml-1">Manage</span>
          </button>
        </div>
        <div className="text-slate-300 text-xs lg:text-sm mb-3 lg:mb-4 hidden sm:block">
          Drag agents to add them to your swarm
        </div>
        <div
          className="space-y-2 lg:space-y-3 overflow-y-auto"
          style={{ maxHeight: "calc(50vh - 120px)" }}
        >
          {agents.map((agent) => {
            const category = getAgentCategory(agent.name);
            const IconComponent = categoryIcons[category];
            return (
              <div
                key={agent.id}
                draggable
                onDragStart={(e) => handleDragStart(e, agent, "agent")}
                className="p-3 lg:p-4 bg-slate-800 rounded-xl border border-slate-700 cursor-grab hover:bg-slate-750 hover:border-slate-600 hover:shadow-lg transition-all duration-200 group"
              >
                <div className="flex items-center mb-2">
                  <div
                    className={`w-6 h-6 lg:w-8 lg:h-8 rounded-lg ${categoryColors[category]} flex items-center justify-center text-white mr-2 lg:mr-3`}
                  >
                    {IconComponent && (
                      <IconComponent className="w-3 h-3 lg:w-4 lg:h-4" />
                    )}
                  </div>
                  <div className="font-semibold text-white text-xs lg:text-sm group-hover:text-blue-300 transition-colors truncate">
                    {agent.name}
                  </div>
                </div>
                <div className="text-xs text-slate-300 mb-2 lg:mb-3 leading-relaxed line-clamp-2 hidden sm:block">
                  {agent.description}
                </div>
                <div className="flex justify-between items-center text-xs">
                  <span className="text-slate-400 capitalize px-2 py-1 bg-slate-700 rounded-full hidden sm:inline">
                    {category}
                  </span>
                  {agent.model && (
                    <span className="text-white px-2 py-1 bg-slate-700 rounded-full font-medium">
                      {agent.model}
                    </span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* MCPs Section */}
      <div className="flex-1 p-3 lg:p-4 min-h-0">
        <div className="flex items-center justify-between mb-3 lg:mb-4">
          <h2 className="text-lg lg:text-xl font-bold text-white flex items-center">
            <Wrench className="w-5 h-5 mr-2 text-purple-400" />
            <span className="hidden sm:inline">MCPs</span>
          </h2>
          <button
            onClick={() => setShowMcpModal(true)}
            className="px-2 py-1 text-xs text-slate-400 hover:text-slate-200 border border-slate-600 hover:border-slate-500 rounded hover:bg-slate-700/50 transition-colors flex items-center"
            title="Manage MCP Tools"
          >
            <Settings className="w-3 h-3" />
            <span className="hidden lg:inline ml-1">Manage</span>
          </button>
        </div>
        <div className="text-slate-300 text-xs lg:text-sm mb-3 lg:mb-4 hidden sm:block">
          Drag MCP tools onto agents
        </div>
        <div
          className="space-y-2 lg:space-y-3 overflow-y-auto"
          style={{ maxHeight: "calc(50vh - 120px)" }}
        >
          {mcps.map((mcp) => {
            const category = getMcpCategory(mcp.name);
            const IconComponent = categoryIcons[category];
            return (
              <div
                key={mcp.id}
                draggable
                onDragStart={(e) => handleDragStart(e, mcp, "mcp")}
                className="p-3 lg:p-4 bg-slate-800 rounded-xl border border-slate-700 cursor-grab hover:bg-slate-750 hover:border-slate-600 hover:shadow-lg transition-all duration-200 group"
              >
                <div className="flex items-center mb-2">
                  <div
                    className={`w-6 h-6 lg:w-8 lg:h-8 rounded-lg ${categoryColors[category]} flex items-center justify-center text-white mr-2 lg:mr-3`}
                  >
                    {IconComponent && (
                      <IconComponent className="w-3 h-3 lg:w-4 lg:h-4" />
                    )}
                  </div>
                  <div className="font-semibold text-white text-xs lg:text-sm group-hover:text-purple-300 transition-colors truncate">
                    {mcp.name}
                  </div>
                </div>
                {mcp.description && (
                  <div className="text-xs text-slate-300 mb-2 lg:mb-3 leading-relaxed line-clamp-2 hidden sm:block">
                    {mcp.description}
                  </div>
                )}
                <div className="flex justify-between items-center text-xs">
                  <span className="text-slate-400 capitalize px-2 py-1 bg-slate-700 rounded-full hidden sm:inline">
                    {category}
                  </span>
                  <span className="text-white px-2 py-1 bg-slate-700 rounded-full font-medium">
                    {mcp.type}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Agent Templates Management Modal */}
      {showAgentModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-slate-800 rounded-xl p-6 w-full max-w-2xl mx-4 max-h-[80vh] overflow-y-auto border border-slate-700">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-white flex items-center">
                <Bot className="w-5 h-5 mr-2 text-blue-400" />
                Manage Agent Templates
              </h2>
              <button
                onClick={() => {
                  setShowAgentModal(false);
                  setEditingAgent(null);
                }}
                className="text-slate-400 hover:text-white transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {!editingAgent ? (
              <>
                <div className="mb-4">
                  <button
                    onClick={() => {
                      setEditingAgent({
                        id: "",
                        name: "",
                        description: "",
                        model: "sonnet",
                        allowed_tools: ["Read", "Edit", "Write"],
                      });
                    }}
                    className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-500 transition-colors flex items-center"
                  >
                    <Plus className="w-4 h-4 mr-2" />
                    Add New Template
                  </button>
                </div>

                <div className="space-y-3">
                  {agents.map((agent) => (
                    <div
                      key={agent.id}
                      className="flex items-center justify-between p-4 bg-slate-700 rounded-lg"
                    >
                      <div className="flex-1">
                        <h3 className="font-semibold text-white">
                          {agent.name}
                        </h3>
                        <p className="text-sm text-slate-300">
                          {agent.description}
                        </p>
                        <div className="flex gap-2 mt-2">
                          {agent.model && (
                            <span className="px-2 py-1 bg-slate-600 text-white text-xs rounded">
                              {agent.model}
                            </span>
                          )}
                          <span className="px-2 py-1 bg-slate-600 text-white text-xs rounded">
                            {agent.allowed_tools?.length || 0} tools
                          </span>
                        </div>
                      </div>
                      <div className="flex gap-2">
                        <button
                          onClick={() => setEditingAgent(agent)}
                          className="p-2 text-slate-400 hover:text-white transition-colors"
                          title="Edit template"
                        >
                          <Edit className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => {
                            if (confirm(`Delete template "${agent.name}"?`)) {
                              setAgents(
                                agents.filter((a) => a.id !== agent.id)
                              );
                            }
                          }}
                          className="p-2 text-red-400 hover:text-red-300 transition-colors"
                          title="Delete template"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-white">
                  {editingAgent.id
                    ? "Edit Agent Template"
                    : "Create New Agent Template"}
                </h3>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Name
                  </label>
                  <input
                    type="text"
                    value={editingAgent.name}
                    onChange={(e) =>
                      setEditingAgent({ ...editingAgent, name: e.target.value })
                    }
                    className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                    placeholder="Frontend Developer"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Description
                  </label>
                  <textarea
                    value={editingAgent.description}
                    onChange={(e) =>
                      setEditingAgent({
                        ...editingAgent,
                        description: e.target.value,
                      })
                    }
                    className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                    placeholder="Specializes in React and modern web technologies"
                    rows={3}
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Model
                  </label>
                  <select
                    value={editingAgent.model}
                    onChange={(e) =>
                      setEditingAgent({
                        ...editingAgent,
                        model: e.target.value,
                      })
                    }
                    className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                  >
                    <option value="sonnet">Claude 3.5 Sonnet</option>
                    <option value="opus">Claude 3 Opus</option>
                    <option value="haiku">Claude 3 Haiku</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Tools
                  </label>
                  <div className="flex flex-wrap gap-2 mb-2">
                    {(editingAgent.allowed_tools || []).map((tool, index) => (
                      <span
                        key={index}
                        className="inline-flex items-center px-3 py-1 bg-blue-600 text-white text-sm rounded-full"
                      >
                        {tool}
                        <button
                          onClick={() => {
                            const newTools = [
                              ...(editingAgent.allowed_tools || []),
                            ];
                            newTools.splice(index, 1);
                            setEditingAgent({
                              ...editingAgent,
                              allowed_tools: newTools,
                            });
                          }}
                          className="ml-2 text-blue-200 hover:text-white"
                        >
                          <X className="w-3 h-3" />
                        </button>
                      </span>
                    ))}
                  </div>
                  <input
                    type="text"
                    placeholder="Add tool (e.g., Read, Edit, Bash)"
                    className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        const tool = e.currentTarget.value.trim();
                        if (
                          tool &&
                          !(editingAgent.allowed_tools || []).includes(tool)
                        ) {
                          setEditingAgent({
                            ...editingAgent,
                            allowed_tools: [
                              ...(editingAgent.allowed_tools || []),
                              tool,
                            ],
                          });
                          e.currentTarget.value = "";
                        }
                      }
                    }}
                  />
                </div>

                <div className="flex justify-end gap-3 pt-4">
                  <button
                    onClick={() => setEditingAgent(null)}
                    className="px-4 py-2 text-slate-400 hover:text-white border border-slate-600 rounded-lg hover:border-slate-500 transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={() => {
                      if (!editingAgent.name) {
                        alert("Please enter a name");
                        return;
                      }

                      if (editingAgent.id) {
                        // Update existing
                        setAgents(
                          agents.map((a) =>
                            a.id === editingAgent.id ? editingAgent : a
                          )
                        );
                      } else {
                        // Create new
                        const newAgent = {
                          ...editingAgent,
                          id: editingAgent.name
                            .toLowerCase()
                            .replace(/[^a-z0-9\s]/g, "")
                            .replace(/\s+/g, "-"),
                        };
                        setAgents([...agents, newAgent]);
                      }
                      setEditingAgent(null);
                    }}
                    className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-500 transition-colors"
                  >
                    {editingAgent.id ? "Update" : "Create"}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* MCP Tools Management Modal */}
      {showMcpModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-slate-800 rounded-xl p-6 w-full max-w-2xl mx-4 max-h-[80vh] overflow-y-auto border border-slate-700">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-white flex items-center">
                <Wrench className="w-5 h-5 mr-2 text-purple-400" />
                Manage MCP Tools
              </h2>
              <button
                onClick={() => {
                  setShowMcpModal(false);
                  setEditingMcp(null);
                }}
                className="text-slate-400 hover:text-white transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {!editingMcp ? (
              <>
                <div className="mb-4">
                  <button
                    onClick={() => {
                      setEditingMcp({
                        id: "",
                        name: "",
                        type: "stdio",
                        description: "",
                      });
                    }}
                    className="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-500 transition-colors flex items-center"
                  >
                    <Plus className="w-4 h-4 mr-2" />
                    Add New MCP Tool
                  </button>
                </div>

                <div className="space-y-3">
                  {mcps.map((mcp) => (
                    <div
                      key={mcp.id}
                      className="flex items-center justify-between p-4 bg-slate-700 rounded-lg"
                    >
                      <div className="flex-1">
                        <h3 className="font-semibold text-white">{mcp.name}</h3>
                        {mcp.description && (
                          <p className="text-sm text-slate-300">
                            {mcp.description}
                          </p>
                        )}
                        <div className="flex gap-2 mt-2">
                          <span className="px-2 py-1 bg-slate-600 text-white text-xs rounded">
                            {mcp.type}
                          </span>
                          {mcp.command && (
                            <span className="px-2 py-1 bg-slate-600 text-white text-xs rounded">
                              {mcp.command}
                            </span>
                          )}
                        </div>
                      </div>
                      <div className="flex gap-2">
                        <button
                          onClick={() => setEditingMcp(mcp)}
                          className="p-2 text-slate-400 hover:text-white transition-colors"
                          title="Edit MCP tool"
                        >
                          <Edit className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => {
                            if (confirm(`Delete MCP tool "${mcp.name}"?`)) {
                              setMcps(mcps.filter((m) => m.id !== mcp.id));
                            }
                          }}
                          className="p-2 text-red-400 hover:text-red-300 transition-colors"
                          title="Delete MCP tool"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-white">
                  {editingMcp.id ? "Edit MCP Tool" : "Create New MCP Tool"}
                </h3>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Name
                  </label>
                  <input
                    type="text"
                    value={editingMcp.name}
                    onChange={(e) =>
                      setEditingMcp({ ...editingMcp, name: e.target.value })
                    }
                    className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                    placeholder="Playwright MCP"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Type
                  </label>
                  <select
                    value={editingMcp.type}
                    onChange={(e) =>
                      setEditingMcp({
                        ...editingMcp,
                        type: e.target.value as "stdio" | "sse",
                      })
                    }
                    className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                  >
                    <option value="stdio">stdio</option>
                    <option value="sse">sse</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Description
                  </label>
                  <textarea
                    value={editingMcp.description || ""}
                    onChange={(e) =>
                      setEditingMcp({
                        ...editingMcp,
                        description: e.target.value,
                      })
                    }
                    className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                    placeholder="Browser automation and testing tool"
                    rows={3}
                  />
                </div>

                {editingMcp.type === "stdio" && (
                  <>
                    <div>
                      <label className="block text-sm font-medium text-slate-300 mb-2">
                        Command
                      </label>
                      <input
                        type="text"
                        value={editingMcp.command || ""}
                        onChange={(e) =>
                          setEditingMcp({
                            ...editingMcp,
                            command: e.target.value,
                          })
                        }
                        className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                        placeholder="npx"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-slate-300 mb-2">
                        Arguments
                      </label>
                      <input
                        type="text"
                        value={(editingMcp.args || []).join(" ")}
                        onChange={(e) =>
                          setEditingMcp({
                            ...editingMcp,
                            args: e.target.value
                              .split(" ")
                              .filter((arg) => arg.trim()),
                          })
                        }
                        className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                        placeholder="@playwright/test"
                      />
                      <p className="text-xs text-slate-400 mt-1">
                        Space-separated arguments
                      </p>
                    </div>
                  </>
                )}

                {editingMcp.type === "sse" && (
                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-2">
                      URL
                    </label>
                    <input
                      type="text"
                      value={editingMcp.url || ""}
                      onChange={(e) =>
                        setEditingMcp({ ...editingMcp, url: e.target.value })
                      }
                      className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white"
                      placeholder="http://localhost:3000/mcp"
                    />
                  </div>
                )}

                <div className="flex justify-end gap-3 pt-4">
                  <button
                    onClick={() => setEditingMcp(null)}
                    className="px-4 py-2 text-slate-400 hover:text-white border border-slate-600 rounded-lg hover:border-slate-500 transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={() => {
                      if (!editingMcp.name) {
                        alert("Please enter a name");
                        return;
                      }

                      if (editingMcp.id) {
                        // Update existing
                        setMcps(
                          mcps.map((m) =>
                            m.id === editingMcp.id ? editingMcp : m
                          )
                        );
                      } else {
                        // Create new
                        const newMcp = {
                          ...editingMcp,
                          id: editingMcp.name
                            .toLowerCase()
                            .replace(/[^a-z0-9\s]/g, "")
                            .replace(/\s+/g, "-"),
                        };
                        setMcps([...mcps, newMcp]);
                      }
                      setEditingMcp(null);
                    }}
                    className="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-500 transition-colors"
                  >
                    {editingMcp.id ? "Update" : "Create"}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

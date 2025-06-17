import { useState, useEffect } from 'react';
import { Zap, Plus, Users, X } from 'lucide-react';

export interface SwarmSummary {
  filename: string;
  name: string;
  main: string;
  instances: string[];
}

interface SwarmSidebarProps {
  onSwarmSelect: (swarm: SwarmSummary) => void;
  selectedSwarm: SwarmSummary | null;
  refreshTrigger?: number;
}

export default function SwarmSidebar({ onSwarmSelect, selectedSwarm, refreshTrigger }: SwarmSidebarProps) {
  const [swarms, setSwarms] = useState<SwarmSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showNewSwarmModal, setShowNewSwarmModal] = useState(false);
  const [newSwarmForm, setNewSwarmForm] = useState({
    filename: '',
    name: '',
    description: ''
  });

  useEffect(() => {
    fetchSwarms();
  }, [refreshTrigger]);

  const fetchSwarms = async () => {
    try {
      const response = await fetch('/api/swarms');
      if (!response.ok) throw new Error('Failed to fetch swarms');
      const data = await response.json();
      setSwarms(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  const handleNewSwarm = () => {
    setShowNewSwarmModal(true);
    setNewSwarmForm({
      filename: '',
      name: '',
      description: ''
    });
  };

  const createNewSwarm = async () => {
    if (!newSwarmForm.filename || !newSwarmForm.name) {
      alert('Please fill in both filename and name');
      return;
    }

    let filename = newSwarmForm.filename;
    if (!filename.endsWith('.yml')) {
      filename += '.yml';
    }

    // Create the swarm configuration
    const swarmConfig = {
      version: 1,
      swarm: {
        name: newSwarmForm.name,
        main: 'main_instance',
        instances: {
          main_instance: {
            description: newSwarmForm.description || 'Main coordinator instance',
            directory: '.',
            model: 'sonnet',
            prompt: 'You are the main coordinator for this swarm',
            allowed_tools: ['Read', 'Edit', 'Write', 'Bash'],
            tools: ['Read', 'Edit', 'Write', 'Bash'],
            connections: [],
            mcps: []
          }
        }
      }
    };

    try {
      // Save the new swarm
      const response = await fetch(`/api/swarms/${filename}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ config: swarmConfig }),
      });

      if (!response.ok) {
        throw new Error('Failed to create swarm');
      }

      // Create swarm summary and select it
      const newSwarm: SwarmSummary = {
        filename,
        name: newSwarmForm.name,
        main: 'main_instance',
        instances: ['main_instance']
      };

      // Update swarms list and select the new one
      setSwarms(prev => [...prev, newSwarm]);
      onSwarmSelect(newSwarm);
      setShowNewSwarmModal(false);
    } catch (error) {
      alert('Failed to create swarm: ' + (error as Error).message);
    }
  };

  if (loading) {
    return (
      <div className="w-80 bg-gray-100 border-r border-gray-300 p-4">
        <div className="animate-pulse">Loading swarms...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="w-80 bg-gray-100 border-r border-gray-300 p-4">
        <div className="text-red-600">Error: {error}</div>
        <button 
          onClick={fetchSwarms}
          className="mt-2 px-3 py-1 bg-blue-500 text-white rounded hover:bg-blue-600"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="w-80 lg:w-80 md:w-72 sm:w-64 bg-slate-900 border-r border-slate-700 flex flex-col h-full">
      <div className="p-4 lg:p-6 border-b border-slate-700 flex-shrink-0">
        <div className="flex justify-between items-center">
          <h2 className="text-lg lg:text-xl font-bold text-white flex items-center">
            <Zap className="w-5 h-5 mr-2 text-blue-400" />
            <span className="hidden sm:inline">Swarms</span>
          </h2>
          <button
            onClick={handleNewSwarm}
            className="px-3 py-2 text-sm text-slate-400 hover:text-slate-200 border border-slate-600 hover:border-slate-500 rounded-lg hover:bg-slate-700/50 transition-colors flex items-center"
          >
            <Plus className="w-4 h-4 mr-1" />
            <span className="hidden sm:inline">New</span>
          </button>
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto p-3 lg:p-4 min-h-0">
        {swarms.length === 0 ? (
          <div className="text-slate-300 text-center py-8 lg:py-12">
            <Zap className="w-12 h-12 mx-auto text-slate-400 mb-4" />
            <div className="text-base lg:text-lg font-medium mb-2 text-white">No swarms found</div>
            <div className="text-sm text-slate-400">Create a new one to get started</div>
          </div>
        ) : (
          <div className="space-y-2 lg:space-y-3">
            {swarms.map((swarm) => (
              <div
                key={swarm.filename}
                onClick={() => onSwarmSelect(swarm)}
                className={`p-3 lg:p-4 rounded-xl cursor-pointer transition-all duration-200 ${
                  selectedSwarm?.filename === swarm.filename
                    ? 'bg-blue-600 shadow-lg shadow-blue-500/25 border border-blue-400'
                    : 'bg-slate-800 hover:bg-slate-750 border border-slate-700 hover:border-slate-600 hover:shadow-lg'
                }`}
              >
                <div className={`font-semibold text-sm lg:text-base mb-2 ${
                  selectedSwarm?.filename === swarm.filename ? 'text-white' : 'text-white'
                }`}>{swarm.name}</div>
                <div className={`text-xs lg:text-sm mb-2 font-mono truncate ${
                  selectedSwarm?.filename === swarm.filename ? 'text-blue-100' : 'text-slate-400'
                }`}>{swarm.filename}</div>
                <div className="flex items-center justify-between text-xs">
                  <div className={`truncate mr-2 ${
                    selectedSwarm?.filename === swarm.filename ? 'text-blue-200' : 'text-slate-500'
                  }`}>
                    <span className="font-medium">Main:</span> <span className="hidden sm:inline">{swarm.main}</span>
                  </div>
                  <div className={`px-2 py-1 rounded-full flex items-center ${
                    selectedSwarm?.filename === swarm.filename 
                      ? 'bg-blue-500 text-white' 
                      : 'bg-slate-700 text-slate-300'
                  }`}>
                    <Users className="w-3 h-3 mr-1" />
                    {swarm.instances.length}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* New Swarm Modal */}
      {showNewSwarmModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-slate-800 rounded-xl p-6 w-full max-w-md mx-4 border border-slate-700">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold text-white flex items-center">
                <Zap className="w-5 h-5 mr-2 text-blue-400" />
                Create New Swarm
              </h2>
              <button
                onClick={() => setShowNewSwarmModal(false)}
                className="text-slate-400 hover:text-white transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Swarm Name
                </label>
                <input
                  type="text"
                  value={newSwarmForm.name}
                  onChange={(e) => setNewSwarmForm(prev => ({ ...prev, name: e.target.value }))}
                  className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="My Development Team"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Filename
                </label>
                <input
                  type="text"
                  value={newSwarmForm.filename}
                  onChange={(e) => setNewSwarmForm(prev => ({ ...prev, filename: e.target.value }))}
                  className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="my-dev-team.yml"
                />
                <p className="text-xs text-slate-400 mt-1">
                  Will automatically add .yml extension if not provided
                </p>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Description (optional)
                </label>
                <textarea
                  value={newSwarmForm.description}
                  onChange={(e) => setNewSwarmForm(prev => ({ ...prev, description: e.target.value }))}
                  className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="A collaborative development team for my project"
                  rows={3}
                />
              </div>
            </div>

            <div className="flex justify-end gap-3 mt-6">
              <button
                onClick={() => setShowNewSwarmModal(false)}
                className="px-4 py-2 text-slate-400 hover:text-white border border-slate-600 rounded-lg hover:border-slate-500 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={createNewSwarm}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-500 transition-colors"
              >
                Create Swarm
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
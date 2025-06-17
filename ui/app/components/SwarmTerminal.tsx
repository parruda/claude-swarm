import { useState, useEffect, useRef } from 'react';
import { Play, Square, RotateCw, Terminal, AlertCircle, CheckCircle, Clock, Activity, Cpu, MemoryStick, RefreshCw } from 'lucide-react';

interface SwarmTerminalProps {
  swarmFilename: string;
}

interface ExecutionStatus {
  status: 'running' | 'stopped' | 'error';
  logs: string[];
  startTime?: string;
  pid?: number;
  memory?: number;
  cpu?: number;
}

export default function SwarmTerminal({ swarmFilename }: SwarmTerminalProps) {
  const [executionStatus, setExecutionStatus] = useState<ExecutionStatus>({
    status: 'stopped',
    logs: [],
  });
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [inputValue, setInputValue] = useState('');
  const [isSendingInput, setIsSendingInput] = useState(false);
  const terminalRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  // Auto-scroll terminal to bottom when new logs arrive (only when log count actually increases)
  const prevLogCount = useRef(0);
  useEffect(() => {
    if (terminalRef.current && executionStatus.logs.length > prevLogCount.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
    prevLogCount.current = executionStatus.logs.length;
  }, [executionStatus.logs]);

  // Auto-focus input when execution starts
  useEffect(() => {
    if (executionStatus.status === 'running' && inputRef.current) {
      setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
    }
  }, [executionStatus.status]);

  // Poll for execution status and logs when running
  useEffect(() => {
    const pollExecution = async () => {
      try {
        const encodedFilename = encodeURIComponent(swarmFilename);
        const response = await fetch(`/api/swarms/${encodedFilename}?action=execution`);
        if (response.ok) {
          const data = await response.json();
          setExecutionStatus(data);
          setError(null);
        }
      } catch (err) {
        console.error('Failed to poll execution status:', err);
      }
    };

    // Poll immediately
    pollExecution();

    // Set up polling interval if running
    if (executionStatus.status === 'running') {
      intervalRef.current = setInterval(pollExecution, 1000); // Poll every second
    } else {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    }

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [swarmFilename, executionStatus.status]);

  const startExecution = async () => {
    setIsLoading(true);
    setError(null);
    
    try {
      const encodedFilename = encodeURIComponent(swarmFilename);
      const response = await fetch(`/api/swarms/${encodedFilename}?action=execution`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ action: 'start' }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Failed to start execution');
      }

      const result = await response.json();
      setExecutionStatus(prev => ({
        ...prev,
        status: 'running',
        logs: [...prev.logs, result.message || 'Starting execution...']
      }));
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const stopExecution = async () => {
    setIsLoading(true);
    setError(null);
    
    try {
      const encodedFilename = encodeURIComponent(swarmFilename);
      const response = await fetch(`/api/swarms/${encodedFilename}?action=execution`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ action: 'stop' }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Failed to stop execution');
      }

      const result = await response.json();
      setExecutionStatus(prev => ({
        ...prev,
        status: 'stopped',
        logs: [...prev.logs, result.message || 'Execution stopped']
      }));
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const clearLogs = () => {
    setExecutionStatus(prev => ({
      ...prev,
      logs: []
    }));
  };

  const restartExecution = async () => {
    setIsLoading(true);
    setError(null);
    
    try {
      const encodedFilename = encodeURIComponent(swarmFilename);
      const response = await fetch(`/api/swarms/${encodedFilename}?action=execution`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ action: 'restart' }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Failed to restart execution');
      }

      const result = await response.json();
      setExecutionStatus(prev => ({
        ...prev,
        status: 'running',
        logs: [...prev.logs, 'Restarting execution...', result.message || 'Execution restarted']
      }));
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const sendInput = async () => {
    if (!inputValue.trim() || isSendingInput) return;
    
    setIsSendingInput(true);
    setError(null);
    
    try {
      const encodedFilename = encodeURIComponent(swarmFilename);
      const response = await fetch(`/api/swarms/${encodedFilename}?action=execution`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ action: 'input', input: inputValue }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Failed to send input');
      }

      setInputValue('');
      
      // Focus back to input field
      setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
      
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsSendingInput(false);
    }
  };

  const handleInputKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      sendInput();
    }
  };

  const getStatusIcon = () => {
    switch (executionStatus.status) {
      case 'running':
        return <Clock className="w-4 h-4 text-blue-400 animate-pulse" />;
      case 'error':
        return <AlertCircle className="w-4 h-4 text-red-400" />;
      case 'stopped':
        return <CheckCircle className="w-4 h-4 text-green-400" />;
      default:
        return <Terminal className="w-4 h-4 text-slate-400" />;
    }
  };

  const getStatusText = () => {
    switch (executionStatus.status) {
      case 'running':
        return 'Running';
      case 'error':
        return 'Error';
      case 'stopped':
        return 'Stopped';
      default:
        return 'Ready';
    }
  };

  const getStatusColor = () => {
    switch (executionStatus.status) {
      case 'running':
        return 'text-blue-400';
      case 'error':
        return 'text-red-400';
      case 'stopped':
        return 'text-green-400';
      default:
        return 'text-slate-400';
    }
  };

  return (
    <div className="h-full flex flex-col bg-slate-900 border border-slate-700 rounded-lg">
      {/* Terminal Header */}
      <div className="flex items-center justify-between p-4 border-b border-slate-700 bg-slate-800 rounded-t-lg">
        <div className="flex items-center gap-3">
          <Terminal className="w-5 h-5 text-slate-400" />
          <h3 className="font-semibold text-white">Swarm Execution</h3>
          <div className="flex items-center gap-2">
            {getStatusIcon()}
            <span className={`text-sm font-medium ${getStatusColor()}`}>
              {getStatusText()}
            </span>
          </div>
          
          {/* Process Monitoring */}
          {executionStatus.status === 'running' && executionStatus.pid && (
            <div className="flex items-center gap-4 ml-4 text-xs text-slate-400">
              <div className="flex items-center gap-1">
                <Activity className="w-3 h-3" />
                <span>PID: {executionStatus.pid}</span>
              </div>
              {executionStatus.memory !== undefined && (
                <div className="flex items-center gap-1">
                  <MemoryStick className="w-3 h-3" />
                  <span>Memory: {executionStatus.memory}MB</span>
                </div>
              )}
              {executionStatus.cpu !== undefined && (
                <div className="flex items-center gap-1">
                  <Cpu className="w-3 h-3" />
                  <span>CPU: {executionStatus.cpu}%</span>
                </div>
              )}
            </div>
          )}
        </div>
        
        <div className="flex items-center gap-2">
          <button
            onClick={clearLogs}
            className="p-2 text-slate-400 hover:text-white border border-slate-600 hover:border-slate-500 rounded transition-colors"
            title="Clear logs"
          >
            <RotateCw className="w-4 h-4" />
          </button>
          
          {executionStatus.status === 'error' && (
            <button
              onClick={restartExecution}
              disabled={isLoading}
              className="px-3 py-2 bg-orange-600 hover:bg-orange-500 disabled:bg-orange-800 text-white rounded flex items-center gap-2 transition-colors"
            >
              <RefreshCw className="w-4 h-4" />
              {isLoading ? 'Restarting...' : 'Restart'}
            </button>
          )}
          
          {executionStatus.status === 'running' ? (
            <button
              onClick={stopExecution}
              disabled={isLoading}
              className="px-3 py-2 bg-red-600 hover:bg-red-500 disabled:bg-red-800 text-white rounded flex items-center gap-2 transition-colors"
            >
              <Square className="w-4 h-4" />
              {isLoading ? 'Stopping...' : 'Stop'}
            </button>
          ) : (
            <button
              onClick={startExecution}
              disabled={isLoading}
              className="px-3 py-2 bg-green-600 hover:bg-green-500 disabled:bg-green-800 text-white rounded flex items-center gap-2 transition-colors"
            >
              <Play className="w-4 h-4" />
              {isLoading ? 'Starting...' : 'Start'}
            </button>
          )}
        </div>
      </div>

      {/* Error Display */}
      {error && (
        <div className="p-3 bg-red-900/50 border-b border-red-700 text-red-200 text-sm">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4" />
            {error}
          </div>
        </div>
      )}

      {/* Terminal Output */}
      <div 
        ref={terminalRef}
        className="flex-1 p-4 bg-black text-green-400 font-mono text-sm overflow-y-auto min-h-0"
        style={{ 
          fontFamily: 'ui-monospace, SFMono-Regular, "SF Mono", Monaco, Consolas, "Liberation Mono", "Courier New", monospace'
        }}
      >
        {executionStatus.logs.length === 0 ? (
          <div className="text-slate-500 italic">
            {executionStatus.status === 'running' 
              ? 'Waiting for output...' 
              : 'No execution logs. Click Start to begin.'}
          </div>
        ) : (
          <div className="space-y-1">
            {executionStatus.logs.map((log, index) => (
              <div 
                key={index}
                className={`${
                  log.includes('[ERROR]') || log.includes('[STDERR]') 
                    ? 'text-red-400' 
                    : log.includes('[STDOUT]')
                    ? 'text-green-400'
                    : 'text-slate-300'
                }`}
              >
                <span className="text-slate-500 mr-2">
                  {String(index + 1).padStart(3, '0')}
                </span>
                {log}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Input Area - Only show when running */}
      {executionStatus.status === 'running' && (
        <div className="p-3 border-t border-slate-700 bg-slate-900 rounded-b-lg">
          <div className="flex items-center gap-2">
            <span className="text-green-400 font-mono text-sm">$</span>
            <input
              ref={inputRef}
              type="text"
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              onKeyDown={handleInputKeyDown}
              disabled={isSendingInput}
              placeholder="Type command and press Enter..."
              className="flex-1 bg-black text-green-400 font-mono text-sm px-2 py-1 rounded border border-slate-600 focus:border-green-500 focus:outline-none placeholder-slate-500"
              style={{
                fontFamily: 'ui-monospace, SFMono-Regular, "SF Mono", Monaco, Consolas, "Liberation Mono", "Courier New", monospace'
              }}
            />
            <button
              onClick={sendInput}
              disabled={!inputValue.trim() || isSendingInput}
              className="px-3 py-1 bg-green-600 hover:bg-green-500 disabled:bg-green-800 disabled:opacity-50 text-white text-sm rounded transition-colors"
            >
              {isSendingInput ? 'Sending...' : 'Send'}
            </button>
          </div>
          <div className="mt-1 text-xs text-slate-500">
            Try: help, /instances, /config, /task &lt;instance&gt; &lt;description&gt;, /session-info
          </div>
        </div>
      )}

      {/* Terminal Footer */}
      {executionStatus.startTime && (
        <div className="px-4 py-2 border-t border-slate-700 bg-slate-800 text-xs text-slate-400">
          Started: {new Date(executionStatus.startTime).toLocaleString()}
        </div>
      )}
    </div>
  );
}
import { useState, useEffect } from "react";
import { useSocket } from "./hooks/useSocket.js";
import Sidebar from "./components/Sidebar.jsx";
import Dashboard from "./components/Dashboard.jsx";
import TrafficLog from "./components/TrafficLog.jsx";
import WorkspaceView from "./components/WorkspaceView.jsx";
import TerminalView from "./components/TerminalView.jsx";

export default function App() {
  const { connected, stats, traffic, clearTraffic, surfaces, terminalScreens } =
    useSocket();
  const [view, setView] = useState("dashboard");
  const [selectedWorkspace, setSelectedWorkspace] = useState(null);
  const [selectedSurface, setSelectedSurface] = useState(null);
  const [workspaces, setWorkspaces] = useState([]);

  useEffect(() => {
    fetch("/api/workspaces")
      .then((r) => r.json())
      .then(setWorkspaces)
      .catch(() => setWorkspaces([]));
  }, []);

  function handleSelectWorkspace(ws) {
    setSelectedWorkspace(ws);
    setView("workspace");
  }

  function handleSelectSurface(surface) {
    setSelectedSurface(surface);
    setView("terminal");
  }

  return (
    <div className="app">
      <Sidebar
        connected={connected}
        stats={stats}
        workspaces={workspaces}
        surfaces={surfaces}
        currentView={view}
        selectedWorkspace={selectedWorkspace}
        selectedSurface={selectedSurface}
        onNavigate={setView}
        onSelectWorkspace={handleSelectWorkspace}
        onSelectSurface={handleSelectSurface}
      />
      <main className="main-content">
        {view === "dashboard" && (
          <Dashboard stats={stats} traffic={traffic} />
        )}
        {view === "traffic" && (
          <TrafficLog traffic={traffic} onClear={clearTraffic} />
        )}
        {view === "workspace" && selectedWorkspace && (
          <WorkspaceView
            workspace={selectedWorkspace}
            traffic={traffic}
            terminalScreens={terminalScreens}
            onSelectSurface={handleSelectSurface}
          />
        )}
        {view === "terminal" && selectedSurface && (
          <TerminalView
            surface={selectedSurface}
            terminalScreens={terminalScreens}
          />
        )}
      </main>
    </div>
  );
}

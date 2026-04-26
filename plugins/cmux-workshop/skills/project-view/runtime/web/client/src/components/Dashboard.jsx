import StatsCards from "./StatsCards.jsx";
import MethodsTable from "./MethodsTable.jsx";
import TrafficLog from "./TrafficLog.jsx";

export default function Dashboard({ stats, traffic }) {
  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <h2>Dashboard</h2>
      </div>
      <StatsCards stats={stats} />
      <div className="dashboard-grid">
        <MethodsTable stats={stats} />
        <div className="panel live-traffic-panel">
          <div className="panel-header">Live Traffic</div>
          <TrafficLog traffic={traffic.slice(-50)} />
        </div>
      </div>
    </div>
  );
}

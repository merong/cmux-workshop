export default function StatsCards({ stats }) {
  if (!stats) return null;

  const cards = [
    {
      label: "Total Requests",
      value: stats.requests?.toLocaleString() ?? "—",
      sub: `↑ ${stats.recentRequests ?? 0}/min`,
      color: "var(--cyan)",
    },
    {
      label: "Total Responses",
      value: stats.responses?.toLocaleString() ?? "—",
      sub: `↑ ${stats.recentResponses ?? 0}/min`,
      color: "var(--green)",
    },
    {
      label: "Avg Latency",
      value: `${stats.avgLatency ?? 0}ms`,
      sub: `p99: ${stats.p99Latency ?? 0}ms`,
      color: "var(--yellow)",
    },
    {
      label: "Error Rate",
      value: `${stats.errorRate ?? 0}%`,
      sub: `${stats.errorCount ?? 0} errors`,
      color: "var(--red)",
    },
  ];

  return (
    <div className="stats-cards">
      {cards.map((c) => (
        <div key={c.label} className="stat-card">
          <div className="stat-label">{c.label}</div>
          <div className="stat-value" style={{ color: c.color }}>
            {c.value}
          </div>
          <div className="stat-sub">{c.sub}</div>
        </div>
      ))}
    </div>
  );
}

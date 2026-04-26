export default function MethodsTable({ stats }) {
  if (!stats?.methodCounts) return null;

  const methods = Object.entries(stats.methodCounts);
  if (methods.length === 0) {
    return (
      <div className="panel">
        <div className="panel-header">Top Methods</div>
        <div className="panel-body dim">No data yet</div>
      </div>
    );
  }

  return (
    <div className="panel">
      <div className="panel-header">Top Methods (1min)</div>
      <div className="panel-body">
        {methods.map(([method, count]) => (
          <div key={method} className="method-row">
            <span className="method-name">{method}</span>
            <span className="method-count">{count}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

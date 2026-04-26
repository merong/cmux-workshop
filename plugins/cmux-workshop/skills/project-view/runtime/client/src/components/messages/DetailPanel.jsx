import React, { useEffect, useMemo, useState } from "react";

function shortenValue(value, maxLength) {
  if (!value) return "";
  if (value.length <= maxLength) return value;

  const visible = Math.max(4, Math.floor((maxLength - 1) / 2));
  return `${value.slice(0, visible)}…${value.slice(-visible)}`;
}

export default function DetailPanel({ panelId, detailHash, detailRef, isOpen, onClose }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [retryToken, setRetryToken] = useState(0);
  const summary = useMemo(() => {
    const refSummary = shortenValue(detailRef, 24);
    const hashSummary = shortenValue(detailHash, 12);
    return [refSummary, hashSummary].filter(Boolean).join(" • ");
  }, [detailHash, detailRef]);

  useEffect(() => {
    if (!detailHash || !detailRef || !isOpen) {
      setData(null);
      setLoading(false);
      setError(null);
      return undefined;
    }

    const controller = new AbortController();

    setData(null);
    setLoading(true);
    setError(null);

    fetch(
      `/api/events/detail?hash=${encodeURIComponent(detailHash)}&ref=${encodeURIComponent(detailRef)}`,
      { signal: controller.signal }
    )
      .then((response) => response.json())
      .then((result) => {
        setData(result.detail || result.error);
        setLoading(false);
      })
      .catch((nextError) => {
        if (nextError.name === "AbortError") return;
        setError(nextError.message);
        setLoading(false);
      });

    return () => controller.abort();
  }, [detailHash, detailRef, isOpen, retryToken]);

  const body = loading ? (
    <div className="detail-panel__skeleton" aria-hidden="true">
      <span className="detail-panel__skeleton-line detail-panel__skeleton-line--lg" />
      <span className="detail-panel__skeleton-line" />
      <span className="detail-panel__skeleton-line detail-panel__skeleton-line--sm" />
    </div>
  ) : error ? (
    <div className="detail-panel__error" role="alert">
      <span className="detail-panel__error-icon" aria-hidden="true">!</span>
      <span className="detail-panel__error-text">Failed: {error}</span>
      <button
        className="detail-panel__retry"
        type="button"
        onClick={() => setRetryToken((value) => value + 1)}
      >
        Retry
      </button>
    </div>
  ) : (
    <pre className="detail-content">
      {typeof data === "string" ? data : JSON.stringify(data, null, 2)}
    </pre>
  );

  return (
    <div
      id={panelId}
      className={`detail-panel${isOpen ? " is-open" : " is-closed"}`}
      role="region"
      aria-hidden={!isOpen}
      aria-label={summary ? `Detail panel ${summary}` : "Detail panel"}
    >
      <div className="detail-panel__header">
        <div className="detail-panel__summary">
          <span className="detail-panel__label">detail</span>
          {summary && <span className="detail-panel__key">{summary}</span>}
        </div>
        <button
          className="detail-panel__close"
          type="button"
          aria-label="Hide detail"
          onClick={onClose}
        >
          ×
        </button>
      </div>
      <div className="detail-panel__body">
        {body}
      </div>
    </div>
  );
}

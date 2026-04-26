import { useRef, useState, useCallback, useEffect } from "react";

export function useAutoScroll(deps) {
  const ref = useRef(null);
  const [atBottom, setAtBottom] = useState(true);

  const handleScroll = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const isAtBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 50;
    setAtBottom(isAtBottom);
  }, []);

  const scrollToBottom = useCallback(() => {
    const el = ref.current;
    if (el) {
      el.scrollTop = el.scrollHeight;
      setAtBottom(true);
    }
  }, []);

  // Auto-scroll when deps change and already at bottom
  useEffect(() => {
    if (atBottom) {
      scrollToBottom();
    }
  }, [deps, atBottom, scrollToBottom]);

  return { ref, atBottom, handleScroll, scrollToBottom };
}

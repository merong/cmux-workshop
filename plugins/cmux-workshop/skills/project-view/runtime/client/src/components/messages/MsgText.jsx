import React from "react";
import { renderMarkdown } from "../../utils/markdown";

export default function MsgText({ text, mode }) {
  if (mode === "md") {
    return (
      <div
        className="msg-text md-rendered"
        dangerouslySetInnerHTML={{ __html: renderMarkdown(text) }}
      />
    );
  }
  return <div className="msg-text">{text}</div>;
}

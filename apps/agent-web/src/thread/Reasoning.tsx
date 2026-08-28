import { useState } from "react";
import type { ReasoningMessagePartComponent } from "@assistant-ui/react";

/**
 * 模型的思考过程，默认折叠。
 *
 * 默认展开会把真正的回答挤到屏幕外——孕期用户要的是结论，过程是需要时才查的。
 * 但它必须**可见地存在**：完全不显示的话，「它到底在干什么」就又回到了从前那句
 * 「正在整理回答…」。
 */
export const Reasoning: ReasoningMessagePartComponent = ({ text, status }) => {
  const [open, setOpen] = useState(false);
  const running = status?.type === "running";

  return (
    <div className={`reasoning${running ? " reasoning--running" : ""}`}>
      <button
        type="button"
        className="reasoning__toggle"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        {running ? "正在思考…" : "思考过程"}
        <span className="reasoning__chevron" aria-hidden="true">
          {open ? "▾" : "▸"}
        </span>
      </button>
      {open ? <p className="reasoning__body">{text}</p> : null}
    </div>
  );
};

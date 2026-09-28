import type { PageContext } from "../bridge";

/** 输入框上方的「正在看：…」。点 ✕ 之后这段对话不再附带页面内容。 */
export const ContextChip = ({ page, onClear }: { page: PageContext; onClear: () => void }) => (
  <div className="context-chip" role="status">
    <span className="context-chip__label">正在看：{page.title}</span>
    <button
      type="button"
      className="context-chip__clear"
      aria-label="去掉页面上下文"
      onClick={onClear}
    >
      ✕
    </button>
  </div>
);

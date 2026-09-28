import { useApprovalBatch } from "../approvals";
import { approvalCopy } from "./labels";

/**
 * 一条助手消息里待确认项共用的一对按钮。
 *
 * 由消息自己决定是否渲染（只在本条有待确认项时），文案按工具区分——
 * 改期就写「确认改期」，不再一律「收录」。
 *
 * 仍然是一次拍板整组：Eve 的审批批次必须整批一次回才结算。
 */
export const ToolGroupActions = ({ toolNames }: { toolNames: string[] }) => {
  const { decideAll, dispatching, error, retry } = useApprovalBatch();
  if (toolNames.length === 0) return null;

  const copy = approvalCopy(toolNames);
  const multiple = toolNames.length > 1;

  return (
    <div className="tool-group__actions">
      {multiple ? (
        <p className="tool-group__eyebrow">以上 {toolNames.length} 项一起确认</p>
      ) : null}
      {error ? (
        <p className="tool-group__error" role="alert">
          {error}
          <button type="button" className="btn btn--link" onClick={retry}>
            重试
          </button>
        </p>
      ) : null}
      <div className="tool-group__buttons">
        <button
          type="button"
          className="btn btn--primary"
          disabled={dispatching}
          onClick={() => decideAll(true)}
        >
          {dispatching
            ? "正在提交…"
            : multiple
              ? `${copy.confirm}（${toolNames.length}）`
              : copy.confirm}
        </button>
        <button type="button" className="btn" disabled={dispatching} onClick={() => decideAll(false)}>
          {copy.reject}
        </button>
      </div>
    </div>
  );
};

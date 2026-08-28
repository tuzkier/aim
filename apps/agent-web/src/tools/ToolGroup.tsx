import { useApprovalBatch } from "../approvals";

/**
 * 整条助手消息共用的一对确认按钮。
 *
 * 用户说「把这三道菜收进菜谱」时那是**一件事**，不该拆成三次拍板——那既不符合
 * 他的表达，也正是「逐条回复导致批次结算不了」的来源：Eve 的审批批次必须整批
 * 一次回才结算（本地实测，逐条回 `input.resolved` 恒为 0）。
 *
 * 一次拍板、一次回复，产品语义和协议约束在这里刚好对上。
 */
export const ToolGroupActions = () => {
  const { decideAll, pendingCount, dispatching } = useApprovalBatch();
  if (pendingCount === 0) return null;

  const multiple = pendingCount > 1;

  return (
    <div className="tool-group__actions">
      {multiple ? (
        <p className="tool-group__eyebrow">以上 {pendingCount} 项一起确认</p>
      ) : null}
      <div className="tool-group__buttons">
        <button
          type="button"
          className="btn btn--primary"
          disabled={dispatching}
          onClick={() => decideAll(true)}
        >
          {dispatching ? "正在提交…" : multiple ? `全部收录（${pendingCount}）` : "收录"}
        </button>
        <button
          type="button"
          className="btn"
          disabled={dispatching}
          onClick={() => decideAll(false)}
        >
          先不收录
        </button>
      </div>
    </div>
  );
};

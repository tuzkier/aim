import { READ_ONLY_TOOLS, toolTitle } from "./labels";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

/**
 * 没有专用渲染器的工具落到这里。
 *
 * 只读工具（查档案、查待办、查指南）渲染成一行淡的步骤行——「它查了什么」正是
 * 用户想看到的过程，此前这些调用在界面上完全不可见，只有一句「正在整理回答…」。
 * 它们不进「最近处理」台账，因为调用它们不改变任何事实。
 *
 * 写操作没有专用卡时给一张通用卡，至少把工具名和审批按钮露出来，
 * 而不是让一次待确认的写入无声无息地卡在那里。
 */
export const GenericToolView = <TArgs,>(props: ToolRenderProps<TArgs>) => {
  const title = toolTitle(props.toolName);

  if (READ_ONLY_TOOLS.has(props.toolName) && !isAwaitingApproval(props.approval)) {
    const running = props.status?.type === "running";
    return (
      <div className={`step-row${running ? " step-row--running" : ""}`}>
        <span className="step-row__dot" aria-hidden="true" />
        <span className="step-row__title">{title}</span>
        {props.isError ? <span className="step-row__error">失败</span> : null}
      </div>
    );
  }

  return (
    <ToolCard>
      <h3 className="tool-card__title">{title}</h3>
      <ApprovalSlot props={props} />
      <ToolStatusLine props={props} />
    </ToolCard>
  );
};

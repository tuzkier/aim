import { makeAssistantToolUI } from "@assistant-ui/react";
import { formatWhen, useEnsureTask } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { taskId?: string; kind?: "schedule" | "delay"; at?: string };

/** 改期确认卡：标题和原日期取自计划，新日期取自参数。 */
export const RescheduleTaskUI = makeAssistantToolUI({
  toolName: "reschedule_task",
  render: (props: ToolRenderProps<Args>) => <RescheduleCard {...props} />,
});

const RescheduleCard = (props: ToolRenderProps<Args>) => {
  const args = props.args ?? {};
  const task = useEnsureTask(args.taskId);
  const awaiting = isAwaitingApproval(props.approval);
  // 原日期只在待确认时有意义：执行后业务数据会刷新，那时「原日期」已经是新日期了。
  const before = awaiting ? formatWhen(task?.scheduled_for ?? task?.due_at) : null;
  const after = formatWhen(args.at);
  const verb = args.kind === "schedule" ? "安排在" : "截止改到";
  return (
    <ToolCard>
      <p className="tool-card__eyebrow">{awaiting ? "将改期" : "改期"}</p>
      <h3 className="tool-card__title">{task?.title ?? "这项待办"}</h3>
      <p className="tool-card__text">
        {before ? <span className="tool-card__was">{before}</span> : null}
        {before ? " → " : ""}
        {verb} {after ?? "（时间无效）"}
      </p>
      <ApprovalSlot props={props} />
      <ToolStatusLine props={props} />
    </ToolCard>
  );
};

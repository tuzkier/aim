import { makeAssistantToolUI } from "@assistant-ui/react";
import { formatWhen, useEnsureTask } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { taskId?: string };
type Result = { data?: { title?: string } };

/**
 * 删除待办的确认卡。标题取自计划（执行后计划里已经没有它，改用服务端结果里的标题），
 * 删了不能撤销，这一点必须写在卡上。
 */
export const DeleteTaskUI = makeAssistantToolUI({
  toolName: "delete_task",
  render: (props: ToolRenderProps<Args>) => <DeleteTaskCard {...props} />,
});

const DeleteTaskCard = (props: ToolRenderProps<Args>) => {
  const args = props.args ?? {};
  const awaiting = isAwaitingApproval(props.approval);
  const task = useEnsureTask(awaiting ? args.taskId : undefined);
  const title = task?.title ?? (props.result as Result | undefined)?.data?.title;
  const when = awaiting ? formatWhen(task?.scheduled_for ?? task?.due_at) : null;
  return (
    <ToolCard>
      <p className="tool-card__eyebrow">{awaiting ? "将删除待办" : "删除待办"}</p>
      <h3 className="tool-card__title">{title ?? "这项待办"}</h3>
      {when ? <p className="tool-card__meta">{when}</p> : null}
      {awaiting ? <p className="tool-card__disclaimer">删除后无法恢复。</p> : null}
      <ApprovalSlot props={props} />
      <ToolStatusLine props={props} />
    </ToolCard>
  );
};

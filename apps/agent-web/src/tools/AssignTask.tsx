import { makeAssistantToolUI } from "@assistant-ui/react";
import { memberName, useBizData, useEnsureTask } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { taskId?: string; assignedMemberId?: string | null };

/** 指派确认卡：成员称呼取自家庭资料，不采信模型写的名字。 */
export const AssignTaskUI = makeAssistantToolUI({
  toolName: "assign_task",
  render: (props: ToolRenderProps<Args>) => <AssignCard {...props} />,
});

const AssignCard = (props: ToolRenderProps<Args>) => {
  const args = props.args ?? {};
  const task = useEnsureTask(args.taskId);
  const { members } = useBizData();
  const target =
    args.assignedMemberId === null
      ? "不指定负责人"
      : `交给${memberName(args.assignedMemberId ? members.get(args.assignedMemberId) : undefined)}`;
  return (
    <ToolCard>
      <p className="tool-card__eyebrow">{isAwaitingApproval(props.approval) ? "将指派" : "指派"}</p>
      <h3 className="tool-card__title">{task?.title ?? "这项待办"}</h3>
      <p className="tool-card__text">{target}</p>
      <ApprovalSlot props={props} />
      <ToolStatusLine props={props} />
    </ToolCard>
  );
};

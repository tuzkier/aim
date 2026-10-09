import { makeAssistantToolUI } from "@assistant-ui/react";
import { useBizData } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { deleteTaskIds } from "./taskArgs";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { taskIds?: string[]; taskId?: string };
type Result = { data?: { title?: string; tasks?: { title: string }[] } };

/**
 * 删除待办的确认卡。一批只有一张卡、一次确认，列出每一条的标题。
 * 标题取自计划；执行后计划里已经没有它们，改用服务端结果里的标题。
 * 删了不能撤销，这一点必须写在卡上。
 */
export const DeleteTaskUI = makeAssistantToolUI({
  toolName: "delete_task",
  render: (props: ToolRenderProps<Args>) => <DeleteTaskCard {...props} />,
});

const DeleteTaskCard = (props: ToolRenderProps<Args>) => {
  const awaiting = isAwaitingApproval(props.approval);
  const { tasks } = useBizData();
  const data = (props.result as Result | undefined)?.data;
  const titles = awaiting
    ? deleteTaskIds(props.args).map((id) => tasks.get(id)?.title ?? "（没找到这项待办）")
    : (data?.tasks?.map((t) => t.title) ?? (data?.title ? [data.title] : []));
  return (
    <ToolCard>
      <p className="tool-card__eyebrow">
        {awaiting ? "将删除" : "删除"}
        {titles.length > 1 ? ` ${titles.length} 项待办` : "待办"}
      </p>
      {titles.length > 1 ? (
        <ul className="tool-card__list">
          {titles.map((title, index) => (
            <li key={`${title}-${index}`}>{title}</li>
          ))}
        </ul>
      ) : (
        <h3 className="tool-card__title">{titles[0] ?? "这项待办"}</h3>
      )}
      {awaiting ? <p className="tool-card__disclaimer">删除后无法恢复。</p> : null}
      <ApprovalSlot props={props} />
      <ToolStatusLine props={props} />
    </ToolCard>
  );
};

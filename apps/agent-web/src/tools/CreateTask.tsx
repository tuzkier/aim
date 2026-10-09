import { makeAssistantToolUI } from "@assistant-ui/react";
import { formatWhen } from "../bizData";
import { OpenNative } from "./OpenNative";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { taskDrafts, type TaskDraft } from "./taskArgs";
import type { ToolRenderProps } from "./types";

type Args = { tasks?: TaskDraft[]; title?: string; description?: string; dueAt?: string };
type Result = { data?: { task_id?: string } };

/**
 * 新建待办（直接执行档，卡片渲染时通常已经做完了）。一条画详情，多条画成清单——
 * 批量建 38 条时一张卡列全，而不是 38 张卡。
 */
export const CreateTaskUI = makeAssistantToolUI({
  toolName: "create_task",
  render: (props: ToolRenderProps<Args>) => {
    const drafts = taskDrafts(props.args);
    const single = drafts.length === 1 ? drafts[0]! : null;
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">
          {drafts.length > 1 ? `新建 ${drafts.length} 项待办` : "待办"}
        </p>
        {single ? (
          <>
            <h3 className="tool-card__title">{single.title}</h3>
            {single.description ? <p className="tool-card__text">{single.description}</p> : null}
            {formatWhen(single.dueAt) ? (
              <p className="tool-card__meta">{formatWhen(single.dueAt)}</p>
            ) : null}
          </>
        ) : (
          <ul className="tool-card__list">
            {drafts.map((draft, index) => (
              <li key={`${draft.title}-${index}`}>
                {draft.title}
                {formatWhen(draft.dueAt) ? (
                  <span className="tool-card__meta"> · {formatWhen(draft.dueAt)}</span>
                ) : null}
              </li>
            ))}
          </ul>
        )}
        <ApprovalSlot props={props} />
        <ToolStatusLine props={props} />
        {single ? (
          <OpenNative kind="task" id={(props.result as Result | undefined)?.data?.task_id} />
        ) : null}
      </ToolCard>
    );
  },
});

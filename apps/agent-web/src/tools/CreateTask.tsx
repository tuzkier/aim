import { makeAssistantToolUI } from "@assistant-ui/react";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import type { ToolRenderProps } from "./types";

type TaskArgs = {
  title?: string;
  detail?: string;
  dueAt?: string;
  due_at?: string;
};

/** 到期时间用本地时区显示。模型给的是 ISO，直接摆出来用户读不懂。 */
const formatDue = (raw: string | undefined): string | null => {
  if (!raw) return null;
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return null;
  return new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(parsed);
};

export const CreateTaskUI = makeAssistantToolUI({
  toolName: "create_task",
  render: (props: ToolRenderProps<TaskArgs>) => {
    const args = props.args ?? {};
    const due = formatDue(args.dueAt ?? args.due_at);
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">将新建待办</p>
        <h3 className="tool-card__title">{args.title ?? "（无标题）"}</h3>
        {args.detail ? <p className="tool-card__text">{args.detail}</p> : null}
        {due ? <p className="tool-card__meta">{due}</p> : null}
        <ApprovalSlot props={props} />
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});

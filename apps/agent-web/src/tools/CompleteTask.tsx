import { makeAssistantToolUI } from "@assistant-ui/react";
import { ToolCard, ToolStatusLine } from "./ToolCard";
import type { ToolRenderProps } from "./types";

type Result = { data?: { title?: string } };

/** 完成待办是直接执行档，没有确认；标题用服务端结果里的，不用模型参数。 */
export const CompleteTaskUI = makeAssistantToolUI({
  toolName: "complete_task",
  render: (props: ToolRenderProps<{ taskId?: string }>) => {
    const title = (props.result as Result | undefined)?.data?.title;
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">完成待办</p>
        <h3 className="tool-card__title">{title ?? "这项待办"}</h3>
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});

import { makeAssistantToolUI } from "@assistant-ui/react";
import { ToolCard, ToolStatusLine } from "./ToolCard";
import type { ToolRenderProps } from "./types";

type Result = {
  data?: { title?: string; tasks?: { title: string }[]; failed?: { reason: string }[] };
};

/** 完成待办是直接执行档，没有确认；标题用服务端结果里的，不用模型参数。 */
export const CompleteTaskUI = makeAssistantToolUI({
  toolName: "complete_task",
  render: (props: ToolRenderProps<unknown>) => {
    const data = (props.result as Result | undefined)?.data;
    const titles = data?.tasks?.map((t) => t.title) ?? (data?.title ? [data.title] : []);
    const failed = data?.failed ?? [];
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">
          {titles.length > 1 ? `完成 ${titles.length} 项待办` : "完成待办"}
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
        {failed.length ? (
          <p className="tool-card__status tool-card__status--error">
            {failed.length} 项没有完成：{failed.map((f) => f.reason).join("；")}
          </p>
        ) : null}
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});

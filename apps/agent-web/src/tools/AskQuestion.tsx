import { makeAssistantToolUI } from "@assistant-ui/react";
import { ToolCard } from "./ToolCard";
import { askQuestionView } from "./taskArgs";
import type { ToolRenderProps } from "./types";

type Args = Parameters<typeof askQuestionView>[0];

/**
 * 旧对话里残留的提问卡。升级后模型已经不能再发起提问（产品决定不开放），
 * 这里只把当时的问题和选项用中文摆出来，不再露出 `ask_question` 这个工具名。
 */
export const AskQuestionUI = makeAssistantToolUI({
  toolName: "ask_question",
  render: (props: ToolRenderProps<Args>) => {
    const view = askQuestionView(props.args);
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">AIM 当时问你</p>
        <h3 className="tool-card__title">{view.question ?? "一个问题"}</h3>
        {view.options.length ? (
          <ul className="tool-card__list">
            {view.options.map((option) => (
              <li key={option}>{option}</li>
            ))}
          </ul>
        ) : null}
        <p className="tool-card__disclaimer">这是之前对话里的提问，已经不能在这里回答。</p>
      </ToolCard>
    );
  },
});

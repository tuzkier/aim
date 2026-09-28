import { makeAssistantToolUI } from "@assistant-ui/react";
import { useBizData } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { key?: string; value?: unknown };

const show = (value: unknown): string =>
  typeof value === "string" ? value : value === undefined ? "（空）" : JSON.stringify(value);

/** 孕期信息确认卡。它不能撤销，所以原值 → 新值要摆清楚。 */
export const RecordFactUI = makeAssistantToolUI({
  toolName: "record_pregnancy_fact",
  render: (props: ToolRenderProps<Args>) => <RecordFactCard {...props} />,
});

const RecordFactCard = (props: ToolRenderProps<Args>) => {
  const args = props.args ?? {};
  const { facts } = useBizData();
  const previous = args.key ? facts.get(args.key) : undefined;
  return (
    <ToolCard>
      <p className="tool-card__eyebrow">
        {isAwaitingApproval(props.approval) ? "将更新孕期信息" : "孕期信息"}
      </p>
      <h3 className="tool-card__title">{args.key ?? "孕期信息"}</h3>
      <p className="tool-card__text">
        {previous !== undefined ? `${show(previous)} → ` : ""}
        {show(args.value)}
      </p>
      <p className="tool-card__disclaimer">孕期信息更新后不能撤销，确认前请核对。</p>
      <ApprovalSlot props={props} />
      <ToolStatusLine props={props} />
    </ToolCard>
  );
};

import { makeAssistantToolUI } from "@assistant-ui/react";
import { OpenNative } from "./OpenNative";
import { ToolCard, ToolStatusLine } from "./ToolCard";
import type { ToolRenderProps } from "./types";

type Args = {
  recordType?: "symptom" | "checkup" | "note";
  title?: string;
  content?: string;
  symptoms?: string[];
  severity?: number;
  hospital?: string;
};

// 与原生 RecordType.displayName 一致。
const TYPE_NAMES = { symptom: "身体感受", checkup: "产检", note: "备忘" } as const;

const summary = (args: Args): string | null => {
  if (args.recordType === "symptom" && args.symptoms?.length) {
    return `${args.symptoms.join("、")}${args.severity ? ` · 程度 ${args.severity}/5` : ""}`;
  }
  if (args.recordType === "checkup") return args.hospital || null;
  return args.content ?? null;
};

/** 新建记录是直接执行档：卡片显示记了什么，并能点进原生记录详情。 */
export const CreateRecordUI = makeAssistantToolUI({
  toolName: "create_record",
  render: (props: ToolRenderProps<Args>) => {
    const args = props.args ?? {};
    const typeName = TYPE_NAMES[args.recordType ?? "note"];
    const text = summary(args);
    const recordId = (props.result as { data?: { record_id?: string } } | undefined)?.data
      ?.record_id;
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">{typeName}</p>
        <h3 className="tool-card__title">{args.title ?? typeName}</h3>
        {text ? <p className="tool-card__text">{text}</p> : null}
        <ToolStatusLine props={props} />
        <OpenNative kind="record" id={recordId} />
      </ToolCard>
    );
  },
});

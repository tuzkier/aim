import { makeAssistantToolUI } from "@assistant-ui/react";
import { categoryTitle, formTitle, VERDICT_LABELS } from "./labels";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

/**
 * 写入知识条目前的确认卡。
 *
 * 按形态渲染要写入的内容——菜谱出食材和编号步骤，「能不能吃」把结论放最上面。
 * 用户否决的原因通常不是「不该存」，而是「内容不对」，所以必须看得见内容本身，
 * 不能只显示 Eve 默认的 "Approve tool call: create_knowledge"。
 *
 * 审批挂在这一个工具调用上：一轮里三道菜就是三张各自带审批态的卡，互不覆盖。
 * 这正是原来那个「只认第一条」的缺陷在新结构下无法表达的原因。
 */

type KnowledgeArgs = {
  title?: string;
  category?: string;
  form?: string;
  ingredients?: string[];
  steps?: string[];
  purposes?: string[];
  verdict?: string;
  reason?: string;
  body?: string;
  note?: string;
};

const Ingredients = ({ values }: { values?: string[] }) =>
  values?.length ? (
    <section className="tool-card__section">
      <h4 className="tool-card__label">食材</h4>
      <p className="tool-card__text">{values.join("、")}</p>
    </section>
  ) : null;

const Steps = ({ values }: { values?: string[] }) =>
  values?.length ? (
    <section className="tool-card__section">
      <h4 className="tool-card__label">做法</h4>
      <ol className="tool-card__steps">
        {values.map((step, index) => (
          <li key={`${index}-${step}`}>{step}</li>
        ))}
      </ol>
    </section>
  ) : null;

const Verdict = ({ verdict, reason }: { verdict?: string; reason?: string }) => (
  <section className="tool-card__section">
    <p className={`verdict verdict--${verdict ?? "unknown"}`}>
      {(verdict && VERDICT_LABELS[verdict]) ?? "待确认"}
    </p>
    {reason ? <p className="tool-card__text">{reason}</p> : null}
  </section>
);

const Body = ({ text }: { text?: string }) =>
  text ? <p className="tool-card__text">{text}</p> : null;

const FormBody = ({ args }: { args: KnowledgeArgs }) => {
  switch (args.form) {
    case "recipe":
      return (
        <>
          <Ingredients values={args.ingredients} />
          <Steps values={args.steps} />
        </>
      );
    case "food_rule":
      return <Verdict verdict={args.verdict} reason={args.reason} />;
    case "howto":
      return <Steps values={args.steps} />;
    default:
      return <Body text={args.body} />;
  }
};

export const CreateKnowledgeUI = makeAssistantToolUI({
  toolName: "create_knowledge",
  render: (props: ToolRenderProps<KnowledgeArgs>) => {
    const args = props.args ?? {};
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">
          {isAwaitingApproval(props.approval) ? "将收录到" : "已收录到"}
          「{categoryTitle(args.category)}」· {formTitle(args.form)}
        </p>
        <h3 className="tool-card__title">{args.title ?? "（无标题）"}</h3>
        {args.purposes?.length ? (
          <ul className="chips">
            {args.purposes.map((purpose) => (
              <li key={purpose} className="chip">
                {purpose}
              </li>
            ))}
          </ul>
        ) : null}
        <FormBody args={args} />
        {args.note ? <p className="tool-card__note">{args.note}</p> : null}
        <p className="tool-card__disclaimer">
          {/* 固定文案，不接受模型生成的内容——它是产品承诺。 */}
          AIM 依据对话整理，可能有误。收录后可以随时删除。
        </p>
        <ApprovalSlot props={props} />
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});

import { makeAssistantToolUI } from "@assistant-ui/react";
import {
  type CheckupMetrics,
  flagMark,
  metricRows,
  type OtherItem,
  sortedOtherItems,
} from "./checkupReport";
import { OpenNative } from "./OpenNative";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

/**
 * 记产检报告前的确认卡。
 *
 * 报告单上的数字是模型读出来的，可能读错，所以卡片要把每一项都摊开给用户核对：
 * 常规指标、其他化验项（标了异常的排前面）、要一起建的「想问医生」。
 * 卡片只摆数字，不解读——异常意味着什么留给医生。
 */

type Args = {
  date?: string;
  hospital?: string;
  metrics?: CheckupMetrics;
  otherItems?: OtherItem[];
  // 兼容蛇形命名：Agent 侧 zod 用驼峰，但别的入口可能原样转发业务接口的参数。
  other_items?: OtherItem[];
  result?: string;
  doctorAdvice?: string;
  followUpQuestions?: string[];
};

const Metrics = ({ metrics }: { metrics?: CheckupMetrics }) => {
  const rows = metricRows(metrics);
  return rows.length ? (
    <section className="tool-card__section">
      <h4 className="tool-card__label">指标</h4>
      <dl className="checkup-metrics">
        {rows.map((row) => (
          <div key={row.key} className="checkup-metrics__row">
            <dt>{row.label}</dt>
            <dd>
              {row.value} <span className="checkup-unit">{row.unit}</span>
            </dd>
          </div>
        ))}
      </dl>
    </section>
  ) : null;
};

const OtherItems = ({ items }: { items?: OtherItem[] }) => {
  const sorted = sortedOtherItems(items);
  return sorted.length ? (
    <section className="tool-card__section">
      <h4 className="tool-card__label">其他化验项</h4>
      <ul className="checkup-items">
        {sorted.map((item, index) => (
          <li
            key={`${index}-${item.name}`}
            className={item.flag ? `checkup-item checkup-item--${item.flag}` : "checkup-item"}
          >
            <span className="checkup-item__name">{item.name}</span>
            <span className="checkup-item__value">
              {item.value}
              {item.unit ? <span className="checkup-unit"> {item.unit}</span> : null}
              {item.flag ? <span className="checkup-item__flag"> {flagMark(item.flag)}</span> : null}
            </span>
            {item.reference ? (
              <span className="checkup-item__reference">参考 {item.reference}</span>
            ) : null}
          </li>
        ))}
      </ul>
    </section>
  ) : null;
};

const TextSection = ({ label, text }: { label: string; text?: string }) =>
  text ? (
    <section className="tool-card__section">
      <h4 className="tool-card__label">{label}</h4>
      <p className="tool-card__text">{text}</p>
    </section>
  ) : null;

const Questions = ({ values }: { values?: string[] }) =>
  values?.length ? (
    <section className="tool-card__section">
      <h4 className="tool-card__label">同时记到「想问医生」</h4>
      <ul className="tool-card__list">
        {values.map((question, index) => (
          <li key={`${index}-${question}`}>{question}</li>
        ))}
      </ul>
    </section>
  ) : null;

export const CreateCheckupReportUI = makeAssistantToolUI({
  toolName: "create_checkup_report",
  render: (props: ToolRenderProps<Args>) => {
    const args = props.args ?? {};
    const meta = [args.date, args.hospital].filter(Boolean).join(" · ");
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">
          {isAwaitingApproval(props.approval) ? "将记下" : "已记下"}一份产检报告
        </p>
        <h3 className="tool-card__title">产检报告</h3>
        {meta ? <p className="tool-card__meta">{meta}</p> : null}
        <Metrics metrics={args.metrics} />
        <OtherItems items={args.otherItems ?? args.other_items} />
        <TextSection label="报告结论" text={args.result} />
        <TextSection label="医生建议" text={args.doctorAdvice} />
        <Questions values={args.followUpQuestions} />
        <p className="tool-card__disclaimer">
          {/* 固定文案，不接受模型生成的内容——它是产品承诺。 */}
          看不清的项目没有填，请核对后确认。AIM 不判断结果意味着什么，异常项请问医生。
        </p>
        <ApprovalSlot props={props} />
        <ToolStatusLine props={props} />
        <OpenNative
          kind="record"
          id={(props.result as { data?: { record_id?: string } } | undefined)?.data?.record_id}
        />
      </ToolCard>
    );
  },
});

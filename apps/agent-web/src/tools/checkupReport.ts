/**
 * 产检报告预览卡用到的纯函数：把工具参数整理成卡片上一行一行的内容。
 *
 * 参数是模型从报告单上读出来的，流式生成时还可能只到一半，所以这里对每个字段
 * 都不做假设——缺了就不显示，类型不对也不显示，不抛错。
 */

import { isAwaitingApproval, type ToolRenderProps } from "./types";

export type CheckupMetrics = {
  weight_kg?: number;
  systolic?: number;
  diastolic?: number;
  fasting_glucose?: number;
  hemoglobin?: number;
  fetal_heart_rate?: number;
  fundal_height_cm?: number;
};

export type OtherItemFlag = "high" | "low" | "abnormal";

export type OtherItem = {
  name?: string;
  value?: string;
  unit?: string;
  reference?: string;
  flag?: OtherItemFlag;
};

export type MetricRow = { key: string; label: string; value: string; unit: string };

const isNumber = (value: unknown): value is number =>
  typeof value === "number" && Number.isFinite(value);

const row = (key: string, label: string, value: unknown, unit: string): MetricRow[] =>
  isNumber(value) ? [{ key, label, value: String(value), unit }] : [];

const bloodPressureRows = ({ systolic, diastolic }: CheckupMetrics): MetricRow[] =>
  isNumber(systolic) && isNumber(diastolic)
    ? [{ key: "blood_pressure", label: "血压", value: `${systolic}/${diastolic}`, unit: "mmHg" }]
    : [...row("systolic", "收缩压", systolic, "mmHg"), ...row("diastolic", "舒张压", diastolic, "mmHg")];

/** 指标表的行，按卡片上的顺序；收缩压和舒张压都有时合并成一行「血压 120/80」。 */
export const metricRows = (metrics: CheckupMetrics | undefined): MetricRow[] => {
  if (!metrics) return [];
  return [
    ...row("weight_kg", "体重", metrics.weight_kg, "kg"),
    ...bloodPressureRows(metrics),
    ...row("fasting_glucose", "空腹血糖", metrics.fasting_glucose, "mmol/L"),
    ...row("hemoglobin", "血红蛋白", metrics.hemoglobin, "g/L"),
    ...row("fetal_heart_rate", "胎心", metrics.fetal_heart_rate, "次/分"),
    ...row("fundal_height_cm", "宫高", metrics.fundal_height_cm, "cm"),
  ];
};

const FLAG_MARKS: Record<OtherItemFlag, string> = { high: "↑", low: "↓", abnormal: "!" };

/**
 * 是不是认得的异常标记。流式生成时 flag 可能只到一半（比如 "hi"），按没有标记处理。
 * 用 hasOwn 而不是 in，免得 "toString" 这类原型上的键混进来。
 */
export const isKnownFlag = (flag: unknown): flag is OtherItemFlag =>
  typeof flag === "string" && Object.hasOwn(FLAG_MARKS, flag);

/**
 * 其他化验项：报告单上标了异常的排在前面，组内保持报告单原来的顺序。
 * 名字还没生成出来的项先不显示。
 */
export const sortedOtherItems = (items: readonly OtherItem[] | undefined): OtherItem[] => {
  const named = (items ?? []).filter((item) => typeof item?.name === "string" && item.name);
  return [...named.filter((item) => isKnownFlag(item.flag)), ...named.filter((item) => !isKnownFlag(item.flag))];
};

/** 异常标记：偏高 ↑、偏低 ↓、其他异常 !；没有或不认得时为空串。 */
export const flagMark = (flag: OtherItemFlag | undefined): string => (isKnownFlag(flag) ? FLAG_MARKS[flag] : "");

/**
 * 卡片抬头。只有用户批准、而且执行成功拿回结果，才能说「已记下」；
 * 被拒绝、超时、取消、执行失败都没有存，不能让人以为存好了。
 */
export const reportHeadline = (
  approval: ToolRenderProps<unknown>["approval"],
  result: unknown,
  isError = false,
): string => {
  if (!approval) return "整理中";
  if (isAwaitingApproval(approval)) return "将记下一份产检报告";
  if (approval.approved === true && !isError) {
    return result === undefined ? "正在记下一份产检报告" : "已记下一份产检报告";
  }
  return "没有记下这份报告";
};

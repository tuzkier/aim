/**
 * 产检报告预览卡用到的纯函数：把工具参数整理成卡片上一行一行的内容。
 *
 * 参数是模型从报告单上读出来的，流式生成时还可能只到一半，所以这里对每个字段
 * 都不做假设——缺了就不显示，类型不对也不显示，不抛错。
 */

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

/**
 * 其他化验项：报告单上标了异常的排在前面，组内保持报告单原来的顺序。
 * 名字还没生成出来的项先不显示。
 */
export const sortedOtherItems = (items: readonly OtherItem[] | undefined): OtherItem[] => {
  const named = (items ?? []).filter((item) => typeof item?.name === "string" && item.name);
  return [...named.filter((item) => item.flag), ...named.filter((item) => !item.flag)];
};

const FLAG_MARKS: Record<OtherItemFlag, string> = { high: "↑", low: "↓", abnormal: "!" };

/** 异常标记：偏高 ↑、偏低 ↓、其他异常 !；没有标记时为空串。 */
export const flagMark = (flag: OtherItemFlag | undefined): string => (flag ? (FLAG_MARKS[flag] ?? "") : "");

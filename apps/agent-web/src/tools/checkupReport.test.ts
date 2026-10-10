import { expect, test } from "vitest";
import { flagMark, metricRows, sortedOtherItems } from "./checkupReport";

test("metrics come out with Chinese names and units in a fixed order", () => {
  expect(
    metricRows({
      fundal_height_cm: 28,
      fetal_heart_rate: 142,
      hemoglobin: 112,
      fasting_glucose: 4.8,
      weight_kg: 62.5,
    }),
  ).toEqual([
    { key: "weight_kg", label: "体重", value: "62.5", unit: "kg" },
    { key: "fasting_glucose", label: "空腹血糖", value: "4.8", unit: "mmol/L" },
    { key: "hemoglobin", label: "血红蛋白", value: "112", unit: "g/L" },
    { key: "fetal_heart_rate", label: "胎心", value: "142", unit: "次/分" },
    { key: "fundal_height_cm", label: "宫高", value: "28", unit: "cm" },
  ]);
});

test("systolic and diastolic merge into one blood pressure row", () => {
  expect(metricRows({ diastolic: 80, systolic: 120 })).toEqual([
    { key: "blood_pressure", label: "血压", value: "120/80", unit: "mmHg" },
  ]);
});

test("a lone systolic or diastolic keeps its own name", () => {
  expect(metricRows({ systolic: 118 })).toEqual([
    { key: "systolic", label: "收缩压", value: "118", unit: "mmHg" },
  ]);
  expect(metricRows({ diastolic: 76 })).toEqual([
    { key: "diastolic", label: "舒张压", value: "76", unit: "mmHg" },
  ]);
});

test("missing or non-numeric metrics are left out", () => {
  expect(metricRows(undefined)).toEqual([]);
  expect(metricRows({})).toEqual([]);
  // 流式生成时参数可能还不完整，不是数字的值不显示。
  expect(metricRows({ weight_kg: "6" as unknown as number, hemoglobin: 0 })).toEqual([
    { key: "hemoglobin", label: "血红蛋白", value: "0", unit: "g/L" },
  ]);
});

test("flagged items go first, each group keeps the report's order", () => {
  const items = [
    { name: "白细胞", value: "6.1" },
    { name: "尿蛋白", value: "+", flag: "abnormal" as const },
    { name: "血小板", value: "210" },
    { name: "总胆汁酸", value: "12.4", flag: "high" as const },
    { name: "铁蛋白", value: "9", flag: "low" as const },
  ];
  expect(sortedOtherItems(items).map((item) => item.name)).toEqual([
    "尿蛋白",
    "总胆汁酸",
    "铁蛋白",
    "白细胞",
    "血小板",
  ]);
  // 不改动传入的数组。
  expect(items[0].name).toBe("白细胞");
});

test("other items tolerate missing input and half-streamed entries", () => {
  expect(sortedOtherItems(undefined)).toEqual([]);
  expect(sortedOtherItems([{ name: "尿糖" }, {}])).toEqual([{ name: "尿糖" }]);
});

test("flags map to arrows", () => {
  expect(flagMark("high")).toBe("↑");
  expect(flagMark("low")).toBe("↓");
  expect(flagMark("abnormal")).toBe("!");
  expect(flagMark(undefined)).toBe("");
});

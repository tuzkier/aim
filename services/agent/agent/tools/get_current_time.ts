import { defineTool } from "eve/tools";
import { z } from "zod";

/** 用户所在时区。孕期 App 的用户都在国内，不做多时区。 */
const ZONE = "Asia/Shanghai";

/**
 * 现在几点、今天星期几。
 *
 * 模型自己判断「今天」「下周三」是不可靠的：它没有时钟，只能从上下文里猜，
 * 而容器跑在 UTC 上——比用户晚 8 小时，跨夜时连日期都是错的。定个「下周三下午」
 * 的待办因此会落到错误的日子。
 *
 * 所有跟日期相关的推算都必须先调这个工具拿到基准，不要从对话里推。
 */
export default defineTool({
  description:
    "Get the current date and time in the user's timezone (Asia/Shanghai, UTC+8). " +
    "Call this before computing any date the user refers to relatively — 今天/明天/" +
    "下周三/这个周末 — and before setting dueAt on a task. Never guess the current " +
    "date from the conversation: you have no clock, and the runtime is on UTC, " +
    "which is 8 hours behind the user.",
  inputSchema: z.object({}),
  outputSchema: z.object({
    iso: z.string().describe("带 +08:00 偏移的当前时刻，可直接用于 dueAt"),
    date: z.string().describe("当天日期，YYYY-MM-DD"),
    time: z.string().describe("当前时刻，HH:mm"),
    weekday: z.string().describe("中文星期，如「星期三」"),
    timezone: z.string(),
  }),
  async execute() {
    const now = new Date();

    // 用 Intl 取该时区的各字段，而不是给 UTC 加 8 小时——后者在夏令时或时区规则
    // 变更时会悄悄错掉，而且拼出来的 ISO 串没有偏移量，下游没法判断基准。
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: ZONE,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    }).formatToParts(now);
    const field = (type: string) => parts.find((part) => part.type === type)?.value ?? "";

    const date = `${field("year")}-${field("month")}-${field("day")}`;
    const time = `${field("hour")}:${field("minute")}`;
    const weekday = new Intl.DateTimeFormat("zh-CN", {
      timeZone: ZONE,
      weekday: "long",
    }).format(now);

    return {
      iso: `${date}T${time}:${field("second")}+08:00`,
      date,
      time,
      weekday,
      timezone: ZONE,
    };
  },
});

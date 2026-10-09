import { z } from "zod";

/**
 * 模型给出的时刻：北京时间的墙上时间，不带时区。
 *
 * 此前工具参数是带偏移的 ISO 串，模型常把「明天下午三点」写成 `T15:00:00Z`——
 * 那是 UTC 15 点，落到用户手里是晚上 11 点。让模型只写墙上时间、由这里补上
 * +08:00，它就没有写错时区的机会；带 Z 或偏移的串直接校验失败，回到模型手里重写。
 */
export const localDateTime = z
  .string()
  .regex(
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/,
    "用北京时间的墙上时刻，格式 YYYY-MM-DDTHH:mm，不要带 Z 或时区偏移",
  )
  .describe("Beijing wall-clock time, YYYY-MM-DDTHH:mm, with NO timezone suffix (no Z, no +08:00)");

export const toShanghaiIso = (local: string): string =>
  `${local.length === 16 ? `${local}:00` : local}+08:00`;

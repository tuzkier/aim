import type { AgentEntry, NativeContext, PageContext } from "./bridge";

/** 原生传来的东西不当可信输入：认不出来就当作 resume。 */
export const resolveEntry = (context: NativeContext): AgentEntry => {
  const raw = context.entry as
    | Partial<{ mode: string; pageContext: PageContext; autoSend: string }>
    | undefined;
  if (!raw || raw.mode !== "new") return { mode: "resume" };
  const entry: { mode: "new"; pageContext?: PageContext; autoSend?: string } = { mode: "new" };
  if (raw.pageContext && typeof raw.pageContext.title === "string") {
    entry.pageContext = {
      title: raw.pageContext.title,
      summary: typeof raw.pageContext.summary === "string" ? raw.pageContext.summary : "",
    };
  }
  if (typeof raw.autoSend === "string" && raw.autoSend.trim()) entry.autoSend = raw.autoSend;
  return entry;
};

/**
 * 标签存在期间每一轮都附上页面上下文。
 *
 * 用 Eve 的 clientContext：只进这一轮的模型调用、不写历史，所以气泡里不会出现，
 * 也不用在消息里藏标记。
 */
export const withPageContext = <T extends object>(input: T, page: PageContext | null): T =>
  page ? { ...input, clientContext: { page } } : input;

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
 * 每一轮附带给模型的上下文：页面标签还在时附上正在看的页面，发过图时附上图片编号。
 *
 * 用 Eve 的 clientContext：只进这一轮的模型调用、不写历史，所以气泡里不会出现，
 * 也不用在消息里藏标记。
 */
export const withTurnContext = <T extends object>(
  input: T,
  context: { page: PageContext | null; images: string | null },
): T => {
  const clientContext: Record<string, unknown> = {};
  if (context.page) clientContext.page = context.page;
  // 本段对话里发过的图片编号：模型挂图时只能用这里给出的编号，不能编造。
  if (context.images) clientContext.images = context.images;
  return Object.keys(clientContext).length ? { ...input, clientContext } : input;
};

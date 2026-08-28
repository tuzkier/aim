import type { ApprovalTransport } from "./approvals";

/**
 * 直连 Eve 的最小传输层，只为「整批回复审批」这一件事存在。
 *
 * 其余所有交互都走 `@assistant-ui/eve`。这里绕过它是因为它的
 * `onRespondToToolApproval` 一次只发一条，而 Eve 的批次必须整批一次回才结算。
 * `eve/react` 的 `respond` 本身收数组，只是适配器没把这条路暴露出来。
 *
 * 送出后不需要在这里读响应：适配器的事件流会收到 `approval.settled` 与
 * `input.resolved`，界面按流更新，状态仍然只有一个来源。
 */
/**
 * 把一段会话的事件从头拉回来，用于冷启动后重建界面。
 *
 * `initialSession` 只告诉运行时「接哪一段、从哪个位置继续」，不会把已经发生过的
 * 事件补回来；页面重新加载后投影状态是空的，于是界面一片空白。运行时为此提供了
 * `initialEvents`——本函数产出的就是它要的那个「有序前缀」。
 *
 * 拉不到就返回空数组：恢复失败应当退化成一段新对话，而不是白屏。
 */
export const fetchSessionEvents = async (
  sessionId: string,
  token: string,
  origin = "",
): Promise<unknown[]> => {
  try {
    const response = await fetch(`${origin}/eve/v1/session/${sessionId}/stream?from=0`, {
      headers: { accept: "application/x-ndjson", authorization: `Bearer ${token}` },
    });
    if (!response.ok || !response.body) return [];

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    const events: unknown[] = [];
    let buffer = "";
    let done = false;

    while (!done) {
      const chunk = await reader.read();
      done = chunk.done;
      buffer += decoder.decode(chunk.value ?? new Uint8Array(), { stream: !done });
      const lines = buffer.split("\n");
      // 最后一段可能是半行，留到下一轮再拼。
      buffer = done ? "" : (lines.pop() ?? "");
      for (const line of lines) {
        const text = line.trim();
        if (!text) continue;
        try {
          events.push(JSON.parse(text));
        } catch {
          // 半行或噪声，跳过。
        }
      }
      // 会话流在轮次之间会挂着不关。读到 session.waiting 就说明这段历史已经完整，
      // 再等下去只会卡在一个不会结束的连接上。
      if (events.some((e) => (e as { type?: string })?.type === "session.waiting")) break;
    }
    await reader.cancel().catch(() => {});
    return events;
  } catch {
    return [];
  }
};

export const createEveTransport = (options: {
  sessionId: () => string | undefined;
  token: string;
  origin?: string;
}): ApprovalTransport => ({
  respondAll: async (responses) => {
    const sessionId = options.sessionId();
    if (!sessionId) throw new Error("还没有 Eve 会话，无法回复审批");

    const base = options.origin ?? "";
    const response = await fetch(`${base}/eve/v1/session/${sessionId}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${options.token}`,
      },
      body: JSON.stringify({
        inputResponses: responses.map(({ requestId, approved }) => ({
          requestId,
          // Eve 用 optionId 表达决定；approve / cancel 是审批档的两个固定选项。
          optionId: approved ? "approve" : "cancel",
        })),
      }),
    });

    if (!response.ok) {
      throw new Error(`回复审批失败：HTTP ${response.status}`);
    }
  },
});

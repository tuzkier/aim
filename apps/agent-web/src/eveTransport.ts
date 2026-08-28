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
  // 恢复是锦上添花，不值得让人对着「正在接回上一段对话…」干等。会话 id 失效时
  // 这条流可能永远不吐 session.waiting，没有这个上限界面就再也进不去了。
  timeoutMs = 12000,
): Promise<{ events: unknown[]; nextIndex: number } | null> => {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), timeoutMs);
  try {
    // 有界读取靠 includeTailIndex：响应头 x-eve-stream-tail-index 给出「打开这条流
    // 那一刻的历史末尾」，读到它就收工，不跟活流。
    //
    // 此前是靠「读到 session.waiting 就停」，那是错的——session.waiting 每一轮
    // 结束都会发一次，不是整段历史的结尾。结果是只读回第一轮，后面全丢
    //（实测：全量 347 个事件两轮，被截成 47 个事件一轮）。
    // 中间试过 follow=false，那是客户端选项，HTTP 上不认，等于没加。
    const response = await fetch(
      `${origin}/eve/v1/session/${sessionId}/stream?startIndex=0&includeTailIndex=1`,
      {
        headers: { accept: "application/x-ndjson", authorization: `Bearer ${token}` },
        signal: abort.signal,
      },
    );
    if (!response.ok || !response.body) return null;

    const rawTail = response.headers.get("x-eve-stream-tail-index");
    const tailIndex = rawTail === null ? undefined : Number(rawTail);
    // 拿不到末尾位置就别硬读——那会一直跟着活流直到超时。空历史当新对话处理。
    if (tailIndex === undefined || !Number.isFinite(tailIndex)) return null;

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    const events: unknown[] = [];
    let buffer = "";
    let done = false;
    let reachedTail = tailIndex < 0;

    while (!done && !reachedTail) {
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
          const event = JSON.parse(text) as { streamIndex?: number };
          events.push(event);
          if (typeof event.streamIndex === "number" && event.streamIndex >= tailIndex) {
            reachedTail = true;
          }
        } catch {
          // 半行或噪声，跳过。
        }
      }
    }
    await reader.cancel().catch(() => {});

    // 游标要落在「已经投影过的内容之后」。写死成 0 的话，运行时以为自己还在开头：
    // 发消息之后它从 0 重新拉，新事件被埋在几百条旧事件后面，界面要等很久才动，
    // 用户看到的就是「发出去没反应，重进才看到回复」。
    const lastIndex = events.reduce<number>((max, event) => {
      const index = (event as { streamIndex?: number }).streamIndex;
      return typeof index === "number" && index > max ? index : max;
    }, -1);
    return { events, nextIndex: Math.max(lastIndex + 1, tailIndex + 1) };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
};

export const createEveTransport = (options: {
  sessionId: () => string | undefined;
  token: string;
  origin?: string;
  /**
   * 送出之后让运行时重新跟上这一轮。
   *
   * 整批响应是绕过适配器直接 POST 的，适配器因此不知道发生了什么：那一轮 park
   * 之后它的流已经收了，我们的 POST 在服务端开了新一轮，它不会自己跟上去。
   * 结果是服务端执行完了，卡片却一直停在「待提交」。
   */
  onDispatched: () => void;
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
    options.onDispatched();
  },
});

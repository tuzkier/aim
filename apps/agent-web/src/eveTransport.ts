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

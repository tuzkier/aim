/**
 * 会话游标的持久化。
 *
 * WebView 会被系统回收，页面也可能被刷新。不存游标的话，重新加载就是一段全新的
 * 空对话——用户刚聊到一半的内容凭空消失，而它其实还完整地在 Eve 那边。
 *
 * 存的是 `{ sessionId, streamIndex }`，`useEveAgentRuntime` 的 `initialSession`
 * 直接吃这个形状，恢复时它会重放并跟上仍在进行中的那一轮。
 */

import type { ClientSessionState } from "./types";

const KEY = "aim.agent.session";

/**
 * 按账号分键。同一台设备换账号登录时，绝不能把上一个账号的会话接回来——
 * 那是把另一个人的孕期对话摆在眼前。
 */
const keyFor = (accountKey: string) => `${KEY}.${accountKey}`;

/**
 * 冷启动时从 0 重放，而不是从存下的游标继续。
 *
 * 存的是会话末尾的位置；页面重新加载后投影状态是空的，从末尾续只会得到零条事件，
 * 界面依旧空白。要把整段对话画回来，就得从头重放一遍。游标本身仍然要存——
 * 它带着 sessionId，那才是「接哪一段」的依据。
 */
export const loadSession = (accountKey: string): ClientSessionState | undefined => {
  try {
    const raw = window.localStorage.getItem(keyFor(accountKey));
    if (!raw) return undefined;
    const parsed: unknown = JSON.parse(raw);
    if (
      typeof parsed === "object" &&
      parsed !== null &&
      typeof (parsed as ClientSessionState).sessionId === "string" &&
      typeof (parsed as ClientSessionState).streamIndex === "number"
    ) {
      return { sessionId: (parsed as ClientSessionState).sessionId, streamIndex: 0 };
    }
  } catch {
    // localStorage 可能被禁用或内容损坏。恢复不了就开新的，不该因此白屏。
  }
  return undefined;
};

export const saveSession = (accountKey: string, session: ClientSessionState): void => {
  try {
    window.localStorage.setItem(keyFor(accountKey), JSON.stringify(session));
  } catch {
    // 存不下就算了：下次冷启动会丢这段对话，但不影响当前这段。
  }
};

export const clearSession = (accountKey: string): void => {
  try {
    window.localStorage.removeItem(keyFor(accountKey));
  } catch {
    // 同上。
  }
};

import { useEffect, useRef, useState } from "react";
import { useEveError, useEveReset } from "@assistant-ui/eve";

/**
 * 会话不再活跃时自动接一段新的。
 *
 * Eve 的会话会走到「不再接受新轮次」的状态——从历史里翻出很久以前的一段、或者
 * 运行时那边已经收口了。这时候再发一句，服务端返回 409 `session_not_active`，
 * 错误原文是英文的 "The session is no longer active."，此前被原样甩给用户看。
 *
 * 对用户来说这不是错误，是「刚才那段接不上了」。所以这里不报错，而是清掉存下的
 * 游标、重置运行时，然后用中文说明一句，让他重发即可——内容并没有丢，历史里还在。
 */
const SESSION_INACTIVE_MARKERS = ["session_not_active", "no longer active"];

const isSessionInactive = (error: unknown): boolean => {
  const text =
    error instanceof Error ? `${error.message}` : typeof error === "string" ? error : "";
  return SESSION_INACTIVE_MARKERS.some((marker) => text.includes(marker));
};

export const SessionRecovery = ({ onDiscardStoredSession }: { onDiscardStoredSession: () => void }) => {
  const error = useEveError();
  const reset = useEveReset();
  const [notice, setNotice] = useState<string | null>(null);
  // 一次错误只处理一次：reset 会让 error 短暂保持，不挡住的话会反复重置。
  const handledRef = useRef(false);

  useEffect(() => {
    if (!error) {
      handledRef.current = false;
      return;
    }
    if (!isSessionInactive(error) || handledRef.current) return;
    handledRef.current = true;
    onDiscardStoredSession();
    reset();
    setNotice("刚才那段对话接不上了，已经为你开了新的一段。再说一次就好。");
  }, [error, reset, onDiscardStoredSession]);

  if (!notice) return null;
  return (
    <p className="notice" role="status">
      {notice}
    </p>
  );
};

/**
 * 其余错误的用户可见文案。
 *
 * 直接把服务端的英文原文摆出来，用户读不懂也无从判断该重试还是该放弃。
 * 认得出的就翻译，认不出的给一句通用的——但**不吞掉**：界面上必须留下痕迹，
 * 否则又回到「点了没反应」那种状态。
 */
export const describeError = (error: unknown): string => {
  const text = error instanceof Error ? error.message : String(error ?? "");
  if (text.includes("401") || text.toLowerCase().includes("unauthorized")) {
    return "登录已失效，请退出后重新进入。";
  }
  if (text.includes("429")) {
    return "请求太频繁了，缓一下再试。";
  }
  if (/NetworkError|Failed to fetch|network/i.test(text)) {
    return "网络不通，检查一下连接再试。";
  }
  return "刚才那一步没成功，再试一次。";
};

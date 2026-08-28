import { useEffect, useState } from "react";
import { listSessions, type AgentSessionSummary } from "../sessions";

/**
 * 历史对话。
 *
 * 换成 WebView 之后这块一度整个丢了——原来原生有 `AgentSessionListView`，
 * 用户能翻回更早的对话；只靠冷启动恢复的话只能接回最近一段。这是回退，补回来。
 *
 * 由原生工具栏触发（`window.__aimOpenHistory__`），面板本身在 Web 侧渲染：
 * 切换会话要重建运行时，那是这边的事。
 */
export const HistoryPanel = ({
  token,
  origin,
  currentEveSessionId,
  onPick,
  onClose,
}: {
  token: string;
  origin?: string;
  currentEveSessionId?: string;
  onPick: (session: AgentSessionSummary) => void;
  onClose: () => void;
}) => {
  const [sessions, setSessions] = useState<AgentSessionSummary[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    void listSessions(token, origin).then((list) => {
      if (!cancelled) setSessions(list);
    });
    return () => {
      cancelled = true;
    };
  }, [token, origin]);

  return (
    <div className="history" role="dialog" aria-label="历史对话">
      <div className="history__bar">
        <h2 className="history__title">历史对话</h2>
        <button type="button" className="btn" onClick={onClose}>
          关闭
        </button>
      </div>
      {sessions === null ? (
        <p className="history__empty">正在加载…</p>
      ) : sessions.length === 0 ? (
        <p className="history__empty">还没有别的对话。</p>
      ) : (
        <ul className="history__list">
          {sessions.map((session) => {
            const current = session.eveSessionId === currentEveSessionId;
            return (
              <li key={session.id}>
                <button
                  type="button"
                  className={`history__item${current ? " history__item--current" : ""}`}
                  disabled={current}
                  onClick={() => onPick(session)}
                >
                  <span className="history__item-title">{session.title}</span>
                  <span className="history__item-time">
                    {formatWhen(session.lastActiveAt)}
                    {current ? " · 当前" : ""}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
};

/** 今天只显示时间，更早显示日期——孕期用户一天里会问好几次。 */
const formatWhen = (raw: string): string => {
  const at = new Date(raw);
  if (Number.isNaN(at.getTime())) return "";
  const now = new Date();
  const sameDay =
    at.getFullYear() === now.getFullYear() &&
    at.getMonth() === now.getMonth() &&
    at.getDate() === now.getDate();
  return new Intl.DateTimeFormat("zh-CN",
    sameDay
      ? { hour: "2-digit", minute: "2-digit" }
      : { month: "long", day: "numeric" },
  ).format(at);
};

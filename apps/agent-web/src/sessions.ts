/**
 * 会话目录。
 *
 * Eve 那边只按 id 存事件流，「有哪些对话、分别叫什么」是业务侧的账本
 * （`/api/v1/agent/sessions`）。不登记的话，一段对话在冷启动之后就再也找不回来——
 * 用户手里没有 sessionId，能接回的只有最近那一段。
 */

export interface AgentSessionSummary {
  id: string;
  eveSessionId: string;
  title: string;
  lastActiveAt: string;
}

interface RawSession {
  id: string;
  eve_session_id: string;
  title: string;
  last_active_at: string;
}

const authHeaders = (token: string) => ({
  "content-type": "application/json",
  authorization: `Bearer ${token}`,
});

export const listSessions = async (
  token: string,
  origin = "",
): Promise<AgentSessionSummary[]> => {
  const response = await fetch(`${origin}/api/v1/agent/sessions`, {
    headers: authHeaders(token),
  });
  if (!response.ok) return [];
  const body = (await response.json()) as { sessions?: RawSession[] };
  return (body.sessions ?? []).map((session) => ({
    id: session.id,
    eveSessionId: session.eve_session_id,
    title: session.title,
    lastActiveAt: session.last_active_at,
  }));
};

/**
 * 把新开的一段登记进目录。
 *
 * 标题取第一句话——用户回头翻的时候认的是自己说过什么，不是「对话 3」。
 * 登记失败不该打断对话：目录丢一条，比让用户的问题发不出去轻。
 */
export const registerSession = async (
  token: string,
  eveSessionId: string,
  title: string,
  origin = "",
): Promise<void> => {
  try {
    await fetch(`${origin}/api/v1/agent/sessions`, {
      method: "POST",
      headers: authHeaders(token),
      body: JSON.stringify({ eve_session_id: eveSessionId, title }),
    });
  } catch {
    // 见上：登记失败不影响这段对话本身。
  }
};

/** 把某段顶到最前，让「最近」是真的最近。 */
export const touchSession = async (
  token: string,
  sessionId: string,
  origin = "",
): Promise<void> => {
  try {
    await fetch(`${origin}/api/v1/agent/sessions/${sessionId}`, {
      method: "PATCH",
      headers: authHeaders(token),
      body: JSON.stringify({ touch: true }),
    });
  } catch {
    // 同上。
  }
};

/** 从第一句话里取个标题。太长会把列表撑破，截断而不是换行。 */
export const titleFrom = (text: string): string => {
  const cleaned = text.trim().replace(/\s+/g, " ");
  if (!cleaned) return "新的对话";
  return cleaned.length > 24 ? `${cleaned.slice(0, 24)}…` : cleaned;
};

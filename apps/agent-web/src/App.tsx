import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  AssistantRuntimeProvider,
  ComposerPrimitive,
  MessagePrimitive,
  ThreadPrimitive,
} from "@assistant-ui/react";
import {
  useEveAgentRuntime,
  useEveError,
  useEveEvents,
  useEveReset,
  useEveSession,
} from "@assistant-ui/eve";
import { accountKeyFromToken, loadNativeContext, type NativeContext } from "./bridge";
import { clearSession, loadSession, saveSession } from "./session";
import type { ClientSessionState } from "./types";
import { ApprovalBatchProvider } from "./approvals";
import { createEveTransport, fetchSessionEvents } from "./eveTransport";
import { GenericToolView, ToolRenderers } from "./tools";
import { ToolGroupActions } from "./tools/ToolGroup";
import { Reasoning } from "./thread/Reasoning";
import { HistoryPanel } from "./thread/HistoryPanel";
import { SessionRecovery, describeError } from "./thread/SessionRecovery";
import { registerSession, titleFrom, touchSession, type AgentSessionSummary } from "./sessions";

/** 冷启动或切换会话时接回一段对话所需的全部东西。 */
interface Restored {
  session: ClientSessionState;
  events: unknown[];
}

/**
 * 从事件流里取第一句用户说的话，用作会话标题。
 *
 * 用户回头翻历史时认的是自己问过什么，不是「对话 3」。
 */
const firstUserMessage = (events: readonly unknown[]): string | undefined => {
  for (const event of events) {
    const typed = event as { type?: string; data?: { message?: { content?: unknown } } };
    if (typed.type !== "message.received") continue;
    const content = typed.data?.message?.content;
    if (typeof content === "string" && content.trim()) return content;
    if (Array.isArray(content)) {
      const text = content
        .map((part) => (part as { text?: string })?.text)
        .filter((part): part is string => typeof part === "string")
        .join("");
      if (text.trim()) return text;
    }
  }
  return undefined;
};

/**
 * AIM 的对话面。
 *
 * 流是异质的：文字、思考、工具步骤、内联审批卡按发生顺序排在同一条流里。
 * 审批挂在工具调用 part 上，不是会话级状态——一轮里三件事就是三张各自带审批态
 * 的卡，互不覆盖。
 */

/**
 * 一轮里连续的工具调用合成一组，一起确认。
 *
 * 「把这三道菜收进菜谱」是一件事，不该拆成三次拍板——那既不符合用户的表达，
 * 也是批次回不齐的来源。`groupPartByType` 是 assistant-ui 为这种情况提供的原语。
 */
const AssistantMessage = () => (
  <div className="msg msg--assistant">
    <MessagePrimitive.Parts
      components={{
        Reasoning,
        // 没有专用渲染器的工具走兜底：只读工具收成一行步骤，
        // 写操作至少把名字露出来。
        tools: { Fallback: GenericToolView },
      }}
    />
    <ToolGroupActions />
  </div>
);

const UserMessage = () => (
  <div className="msg msg--user">
    <MessagePrimitive.Parts />
  </div>
);

/**
 * 把「开新对话」暴露给原生工具栏。
 *
 * 原生那颗按钮不该自己去猜 Web 的状态——它只发一个意图，由这里执行：
 * 重置运行时并清掉存下的游标，否则下次冷启动又会把刚丢弃的那段接回来。
 */
const NewConversationBridge = ({ accountKey }: { accountKey: string }) => {
  const reset = useEveReset();
  useEffect(() => {
    window.__aimNewConversation__ = () => {
      clearSession(accountKey);
      reset();
    };
    return () => {
      delete window.__aimNewConversation__;
    };
  }, [reset, accountKey]);
  return null;
};

/**
 * 这一轮失败了。此前 turn.failed / session.failed 在界面上没有任何痕迹。
 *
 * 「会话不再活跃」不走这里——那不是错误，是「刚才那段接不上了」，
 * 由 SessionRecovery 自动开新的一段并给出说明。
 */
const TurnError = () => {
  const error = useEveError();
  if (!error) return null;
  const text = error instanceof Error ? error.message : String(error);
  if (text.includes("session_not_active") || text.includes("no longer active")) return null;
  return (
    <div className="turn-error" role="alert">
      {describeError(error)}
    </div>
  );
};

const Thread = () => (
  <ThreadPrimitive.Root className="thread">
    <ThreadPrimitive.Viewport className="thread__viewport" autoScroll>
      <ThreadPrimitive.Empty>
        <div className="welcome">
          <h2 className="welcome__title">我在这里陪你一起理清</h2>
          <p className="welcome__body">
            可以问孕期变化、最近记录或接下来要做的事。涉及计划变更时，我会先让你确认。
          </p>
        </div>
      </ThreadPrimitive.Empty>
      <ThreadPrimitive.Messages components={{ UserMessage, AssistantMessage }} />
      <TurnError />
    </ThreadPrimitive.Viewport>
    <ComposerPrimitive.Root className="composer">
      <ComposerPrimitive.Input
        className="composer__input"
        placeholder="告诉我你现在在担心什么"
        rows={1}
      />
      <ComposerPrimitive.Send className="composer__send">发送</ComposerPrimitive.Send>
    </ComposerPrimitive.Root>
  </ThreadPrimitive.Root>
);

/**
 * 攒批回复需要当前会话 id，而 `useEveSession` 只能在 runtime 之内读，
 * 所以这一层必须待在 `AssistantRuntimeProvider` 里面。
 */
const ApprovalBridge = ({
  context,
  runtime,
  children,
}: {
  context: NativeContext;
  runtime: ReturnType<typeof useEveAgentRuntime>;
  children: ReactNode;
}) => {
  const session = useEveSession();
  const events = useEveEvents();
  // 用 ref 而不是把 sessionId 塞进 useMemo 依赖：transport 的身份一变，
  // 攒批 effect 就会重跑，可能把已经送出的批次再送一次。
  const sessionIdRef = useRef<string | undefined>(undefined);
  sessionIdRef.current = session?.sessionId;

  // 游标一变就落盘。WebView 被系统回收后靠它接回原来那段对话，
  // 否则用户刚聊到一半的内容会凭空消失——而它其实还完整地在 Eve 那边。
  useEffect(() => {
    if (session) saveSession(accountKeyFromToken(context.token), session);
  }, [session, context.token]);

  // 登记进目录，否则冷启动之后只找得回最近一段。
  //
  // 等到第一句话到了才登记：sessionId 出现得比 message.received 早，
  // 一拿到 id 就登记的话标题永远是「新的对话」，翻历史时全是一样的条目。
  // 一句话都没有的空会话本来也不值得进目录。
  // 用 ref 记已登记过的 id：session 每收一批事件就变一次，不能每次都 POST。
  const registeredRef = useRef(new Set<string>());
  useEffect(() => {
    const id = session?.sessionId;
    if (!id || registeredRef.current.has(id)) return;
    const opening = firstUserMessage(events);
    if (!opening) return;
    registeredRef.current.add(id);
    void registerSession(context.token, id, titleFrom(opening), context.eveOrigin);
  }, [session?.sessionId, events, context.token, context.eveOrigin]);

  const transport = useMemo(
    () =>
      createEveTransport({
        sessionId: () => sessionIdRef.current,
        token: context.token,
        origin: context.eveOrigin,
        // resume 会跟上服务端刚开的那一轮，approval.settled 与 action.result
        // 才会回到界面上，卡片也才会从「待提交」变成真实结果。
        onDispatched: () => {
          void runtime.threads.reloadMainThread().catch(() => {
            // 跟不上不该打断：内容已经在服务端执行了，下次冷启动也能接回来。
          });
        },
      }),
    [context.token, context.eveOrigin, runtime],
  );

  return <ApprovalBatchProvider transport={transport}>{children}</ApprovalBatchProvider>;
};

/**
 * 把「历史对话」暴露给原生工具栏。面板本身在 Web 侧渲染——
 * 切换会话要重建运行时，那是这边的事。
 */
const HistoryBridge = ({ onOpen }: { onOpen: () => void }) => {
  useEffect(() => {
    window.__aimOpenHistory__ = onOpen;
    return () => {
      delete window.__aimOpenHistory__;
    };
  }, [onOpen]);
  return null;
};

const Conversation = ({
  context,
  restored,
  onSwitch,
  onDiscardStoredSession,
}: {
  context: NativeContext;
  restored: Restored | null;
  onSwitch: (session: AgentSessionSummary) => void;
  onDiscardStoredSession: () => void;
}) => {
  const [historyOpen, setHistoryOpen] = useState(false);
  const runtime = useEveAgentRuntime({
    ...(restored
      ? { initialSession: restored.session, initialEvents: restored.events as never }
      : {}),
    // host 留空 = 同源 /eve/v1/*。原生外壳里由 WKWebView 的拦截转到部署环境，
    // 开发时由 Vite 代理转到本地 Eve。两边都不需要给 Eve 配 CORS。
    ...(context.eveOrigin ? { host: context.eveOrigin } : {}),
    headers: () => ({ authorization: `Bearer ${context.token}` }),
  });

  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <ApprovalBridge context={context} runtime={runtime}>
        <NewConversationBridge accountKey={accountKeyFromToken(context.token)} />
        <HistoryBridge onOpen={() => setHistoryOpen(true)} />
        <SessionRecovery onDiscardStoredSession={onDiscardStoredSession} />
        <ToolRenderers />
        <Thread />
        {historyOpen ? (
          <HistoryPanel
            token={context.token}
            origin={context.eveOrigin}
            currentEveSessionId={restored?.session.sessionId}
            onPick={(picked) => {
              setHistoryOpen(false);
              onSwitch(picked);
            }}
            onClose={() => setHistoryOpen(false)}
          />
        ) : null}
      </ApprovalBridge>
    </AssistantRuntimeProvider>
  );
};

export const App = () => {
  const [context, setContext] = useState<NativeContext | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [restored, setRestored] = useState<Restored | null>(null);
  const [restoring, setRestoring] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  // 拿到会话票之后、开始渲染对话之前，把上一段对话的事件取回来。
  // `initialEvents` 只在运行时创建那一刻生效，所以必须先取完再渲染。
  useEffect(() => {
    if (!context) return;
    const stored = loadSession(accountKeyFromToken(context.token));
    if (!stored) return;
    let cancelled = false;
    setRestoring(true);
    void fetchSessionEvents(stored.sessionId, context.token, context.eveOrigin)
      .then((events) => {
        if (cancelled) return;
        // 一条都没取到就当新对话开始：那段会话可能已经被服务端清掉了。
        if (events.length > 0) setRestored({ session: stored, events });
      })
      .finally(() => {
        if (!cancelled) setRestoring(false);
      });
    return () => {
      cancelled = true;
    };
  }, [context]);

  useEffect(() => {
    let cancelled = false;
    void loadNativeContext()
      .then((next) => {
        if (!cancelled) setContext(next);
      })
      .catch((cause: unknown) => {
        if (!cancelled) setError(cause instanceof Error ? cause.message : String(cause));
      });
    // 原生轮换票据后重新拿一次，避免用户在对话中途被 401 踢掉。
    window.__aimOnContextChanged__ = (next) => setContext(next);
    return () => {
      cancelled = true;
      delete window.__aimOnContextChanged__;
    };
  }, []);

  /** 切到另一段历史对话：取回它的事件，重建运行时，并把它顶到目录最前。 */
  const switchToSession = (picked: AgentSessionSummary) => {
    if (!context) return;
    setRestoring(true);
    setNotice(null);
    void fetchSessionEvents(picked.eveSessionId, context.token, context.eveOrigin)
      .then((events) => {
        if (events.length === 0) {
          // 运行时升级会让旧会话的事件日志读不回来（CORRUPTED_EVENT_LOG）。
          // 目录里还留着条目，内容却没了——说清楚，别把用户丢在一个空白页面上猜。
          setNotice("这段对话的内容已不可用，可能是服务升级导致的。你可以开一段新的。");
          return;
        }
        setRestored({
          session: { sessionId: picked.eveSessionId, streamIndex: 0 },
          events,
        });
        saveSession(accountKeyFromToken(context.token), {
          sessionId: picked.eveSessionId,
          streamIndex: 0,
        });
        void touchSession(context.token, picked.id, context.eveOrigin);
      })
      .finally(() => setRestoring(false));
  };

  if (error) return <div className="fatal">{error}</div>;
  if (!context) return <div className="loading">正在准备…</div>;
  if (restoring) return <div className="loading">正在接回上一段对话…</div>;

  return (
    <div className={`app app--${context.theme}`}>
      {notice ? (
        <p className="notice" role="status">
          {notice}
        </p>
      ) : null}
      <Conversation
        // key 变了运行时就重建。切换会话必须重建：initialSession / initialEvents
        // 只在创建那一刻生效，光换 props 不会让它去接另一段。
        key={restored?.session.sessionId ?? "new"}
        context={context}
        restored={restored}
        onSwitch={switchToSession}
        onDiscardStoredSession={() => {
          clearSession(accountKeyFromToken(context.token));
          setRestored(null);
        }}
      />
    </div>
  );
};

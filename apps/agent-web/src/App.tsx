import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  AssistantRuntimeProvider,
  ComposerPrimitive,
  MessagePrimitive,
  ThreadPrimitive,
} from "@assistant-ui/react";
import { useEveAgentRuntime, useEveError, useEveSession } from "@assistant-ui/eve";
import { accountKeyFromToken, loadNativeContext, type NativeContext } from "./bridge";
import { loadSession, saveSession } from "./session";
import type { ClientSessionState } from "./types";

/** 冷启动时接回上一段对话所需的全部东西。 */
interface Restored {
  session: ClientSessionState;
  events: unknown[];
}
import { ApprovalBatchProvider } from "./approvals";
import { createEveTransport, fetchSessionEvents } from "./eveTransport";
import { GenericToolView, ToolRenderers } from "./tools";
import { ToolGroupActions } from "./tools/ToolGroup";
import { Reasoning } from "./thread/Reasoning";

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

/** 这一轮失败了。此前 turn.failed / session.failed 在界面上没有任何痕迹。 */
const TurnError = () => {
  const error = useEveError();
  if (!error) return null;
  return (
    <div className="turn-error" role="alert">
      {String((error as { message?: string }).message ?? error)}
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
  children,
}: {
  context: NativeContext;
  children: ReactNode;
}) => {
  const session = useEveSession();
  // 用 ref 而不是把 sessionId 塞进 useMemo 依赖：transport 的身份一变，
  // 攒批 effect 就会重跑，可能把已经送出的批次再送一次。
  const sessionIdRef = useRef<string | undefined>(undefined);
  sessionIdRef.current = session?.sessionId;

  // 游标一变就落盘。WebView 被系统回收后靠它接回原来那段对话，
  // 否则用户刚聊到一半的内容会凭空消失——而它其实还完整地在 Eve 那边。
  useEffect(() => {
    if (session) saveSession(accountKeyFromToken(context.token), session);
  }, [session, context.token]);

  const transport = useMemo(
    () =>
      createEveTransport({
        sessionId: () => sessionIdRef.current,
        token: context.token,
        origin: context.eveOrigin,
      }),
    [context.token, context.eveOrigin],
  );

  return <ApprovalBatchProvider transport={transport}>{children}</ApprovalBatchProvider>;
};

const Conversation = ({
  context,
  restored,
}: {
  context: NativeContext;
  restored: Restored | null;
}) => {
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
      <ApprovalBridge context={context}>
        <ToolRenderers />
        <Thread />
      </ApprovalBridge>
    </AssistantRuntimeProvider>
  );
};

export const App = () => {
  const [context, setContext] = useState<NativeContext | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [restored, setRestored] = useState<Restored | null>(null);
  const [restoring, setRestoring] = useState(false);

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

  if (error) return <div className="fatal">{error}</div>;
  if (!context) return <div className="loading">正在准备…</div>;
  if (restoring) return <div className="loading">正在接回上一段对话…</div>;

  return (
    <div className={`app app--${context.theme}`}>
      <Conversation context={context} restored={restored} />
    </div>
  );
};

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  AssistantRuntimeProvider,
  MessagePrimitive,
  ThreadPrimitive,
  useAuiState,
} from "@assistant-ui/react";
import {
  useEveAgentRuntime,
  useEveError,
  useEveEvents,
  useEveReset,
  useEveSession,
} from "@assistant-ui/eve";
import {
  accountKeyFromToken,
  loadNativeContext,
  notifyTurnFinished,
  type AgentEntry,
  type NativeContext,
  type PageContext,
} from "./bridge";
import { resolveEntry, withTurnContext } from "./entry";
import {
  createImageAttachmentAdapter,
  dataUrlToFile,
  imagesContext,
  numberImages,
  type UploadedImage,
} from "./imageAttachments";
import { ContextChip } from "./thread/ContextChip";
import { clearSession, loadSession, saveSession } from "./session";
import type { ClientSessionState } from "./types";
import { ApprovalBatchProvider } from "./approvals";
import { BizDataProvider, useBizData } from "./bizData";
import { ErrorBoundary, MessageFallback } from "./ErrorBoundary";
import { writesIn } from "./turnWrites";
import { createWriteBatcher } from "./writeBatcher";
import { createEveTransport, fetchSessionEvents } from "./eveTransport";
import { GenericToolView, ToolRenderers } from "./tools";
import { ToolGroupActions } from "./tools/ToolGroup";
import { pendingApprovalTools } from "./tools/types";
import { Reasoning } from "./thread/Reasoning";
import { MarkdownText } from "./thread/MarkdownText";
import { HistoryPanel } from "./thread/HistoryPanel";
import { Composer } from "./thread/Composer";
import { MessageImages } from "./thread/MessageImages";
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
    const typed = event as {
      type?: string;
      data?: { message?: unknown; parts?: readonly { type?: string; text?: string }[] };
    };
    if (typed.type !== "message.received") continue;
    // 载荷长这样：{ message: "你好", parts: [{ type: "text", text: "你好" }] }。
    // 我原来读的是 data.message.content——message 是字符串，.content 永远 undefined，
    // 于是标题取不到、会话一直没登记进目录，历史列表就永远是空的。
    const message = typed.data?.message;
    if (typeof message === "string" && message.trim()) return message;
    const fromParts = (typed.data?.parts ?? [])
      .filter((part) => part?.type === "text" && typeof part.text === "string")
      .map((part) => part.text as string)
      .join("");
    if (fromParts.trim()) return fromParts;
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
const AssistantMessage = () => {
  // 按消息算待确认项：按钮只挂在真有待确认项的那条回复下面。
  // 逗号拼成字符串再比较——选择器每次返回新数组会让组件反复重渲染。
  const pending = useAuiState((state) => pendingApprovalTools(state.message.parts).join(","));
  return (
    <div className="msg msg--assistant">
      <ErrorBoundary scope="message" fallback={() => <MessageFallback />}>
        <MessagePrimitive.Parts
          components={{
            // 指令里允许模型用行内加粗和短列表，客户端就必须能渲染它们——
            // 否则 `**待办内容**` 会带着星号摆在用户面前。
            Text: MarkdownText,
            Reasoning,
            // 没有专用渲染器的工具走兜底：只读工具收成一行步骤，
            // 写操作至少把名字露出来。
            tools: { Fallback: GenericToolView },
          }}
        />
        <ToolGroupActions toolNames={pending ? pending.split(",") : []} />
      </ErrorBoundary>
    </div>
  );
};

/** 图片在上、文字气泡在下；只发了图时不留一个空气泡。 */
const UserMessage = () => {
  const hasText = useAuiState((state) =>
    state.message.parts.some((part) => part.type === "text" && part.text.trim() !== ""),
  );
  return (
    <div className="user-turn">
      <MessageImages />
      {hasText ? (
        <div className="msg msg--user">
          <MessagePrimitive.Parts />
        </div>
      ) : null}
    </div>
  );
};

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

const Thread = ({ chip, attachmentError }: { chip?: ReactNode; attachmentError?: string | null }) => (
  <ThreadPrimitive.Root className="thread">
    <ThreadPrimitive.Viewport className="thread__viewport" autoScroll>
      <ThreadPrimitive.Empty>
        {/* 原生头部已经有「AIM · 孕期里的事，说一声就好」，这里再来一遍大标题
            就是同一件事说两次。空态只留一句引导。 */}
        <p className="welcome">
          可以问孕期变化、最近记录或接下来要做的事，也可以拍产检单让我记下来。涉及计划变更时，我会先让你确认。
        </p>
      </ThreadPrimitive.Empty>
      <ThreadPrimitive.Messages components={{ UserMessage, AssistantMessage }} />
      <TurnError />
    </ThreadPrimitive.Viewport>
    <Composer chip={chip} error={attachmentError} />
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
 * AIM 写完东西就让原生刷新，也让卡片用的业务数据跟上。
 *
 * 从挂载那一刻的事件数开始扫：接回历史对话时重放的旧事件不算新写入。
 */
const TurnFinishedBridge = () => {
  const events = useEveEvents();
  const { reload } = useBizData();
  const reloadRef = useRef(reload);
  reloadRef.current = reload;
  const seenRef = useRef<number | null>(null);
  // 一阵写入只刷新一次：批量操作逐条通知会把原生和网页都刷爆。
  const batcherRef = useRef<ReturnType<typeof createWriteBatcher> | null>(null);
  batcherRef.current ??= createWriteBatcher({
    delayMs: 600,
    maxWaitMs: 2000,
    flush: (kinds) => {
      notifyTurnFinished(kinds);
      reloadRef.current();
    },
  });
  useEffect(() => () => batcherRef.current?.dispose(), []);
  useEffect(() => {
    if (seenRef.current === null) {
      seenRef.current = events.length;
      return;
    }
    const fresh = events.slice(seenRef.current);
    seenRef.current = events.length;
    batcherRef.current?.add(writesIn(fresh));
  }, [events]);
  return null;
};

/**
 * 从快捷入口回到 AIM 标签页时，跟上快捷入口里新开的那段。
 *
 * 比的是运行时**当前**的会话 id，而不是页面打开时接回的那段——在本页新开的对话
 * 没有「接回」这回事，拿它比会每次回到标签页都把当前对话重载一遍。
 */
const AppearBridge = ({
  enabled,
  accountKey,
  runtime,
  onSwitch,
}: {
  enabled: boolean;
  accountKey: string;
  runtime: ReturnType<typeof useEveAgentRuntime>;
  onSwitch: (eveSessionId: string) => void;
}) => {
  const session = useEveSession();
  const currentRef = useRef<string | undefined>(undefined);
  currentRef.current = session?.sessionId;
  const onSwitchRef = useRef(onSwitch);
  onSwitchRef.current = onSwitch;
  useEffect(() => {
    if (!enabled) return;
    window.__aimOnAppear__ = () => {
      const stored = loadSession(accountKey);
      if (!stored || stored.sessionId === currentRef.current) return;
      // 正在生成、或者用户已经在输入框里写了东西，就不要把人拽走。
      if (runtime.thread.getState().isRunning) return;
      if (runtime.thread.composer.getState().text.trim()) return;
      onSwitchRef.current(stored.sessionId);
    };
    return () => {
      delete window.__aimOnAppear__;
    };
  }, [enabled, accountKey, runtime]);
  return null;
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
  entry,
  restored,
  onSwitch,
  onAppearSwitch,
  onDiscardStoredSession,
}: {
  context: NativeContext;
  entry: AgentEntry;
  restored: Restored | null;
  onSwitch: (session: AgentSessionSummary) => void;
  onAppearSwitch: (eveSessionId: string) => void;
  onDiscardStoredSession: () => void;
}) => {
  const [historyOpen, setHistoryOpen] = useState(false);
  const [page, setPage] = useState<PageContext | null>(
    entry.mode === "new" ? (entry.pageContext ?? null) : null,
  );
  // prepareSend 在运行时创建时就被捕获，直接读 state 会一直是初值，所以经 ref 读。
  const pageRef = useRef(page);
  pageRef.current = page;

  // 本段对话里上传成功的图片。只记在这次打开的页面里：重开旧对话后再说「把刚才那张存起来」，
  // 模型拿不到编号，会请用户重发（见指令）。
  const imagesRef = useRef<UploadedImage[]>([]);
  const [attachmentError, setAttachmentError] = useState<string | null>(null);
  const runtimeRef = useRef<ReturnType<typeof useEveAgentRuntime> | null>(null);
  const attachmentAdapter = useMemo(
    () =>
      createImageAttachmentAdapter({
        upload: async (blob) => {
          // 网页上下文里孕期编号是可选的（还没建孕期时没有），这时存不了图。
          if (!context.pregnancyId) throw new Error("还没有孕期信息，暂时不能发图片");
          const response = await fetch(
            `${context.eveOrigin ?? ""}/api/v1/pregnancies/${context.pregnancyId}/attachments`,
            {
              method: "POST",
              headers: { authorization: `Bearer ${context.token}`, "content-type": "image/jpeg" },
              body: blob,
            },
          );
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          return ((await response.json()) as { id: string }).id;
        },
        onUploaded: ({ id, order }) => {
          // 这张图属于即将发出的那条用户消息。
          const sent =
            runtimeRef.current?.thread
              .getState()
              .messages.filter((message) => message.role === "user").length ?? 0;
          imagesRef.current = [...imagesRef.current, { id, message: sent + 1, order }];
        },
        onError: setAttachmentError,
      }),
    [context.eveOrigin, context.pregnancyId, context.token],
  );

  const runtime = useEveAgentRuntime({
    ...(restored
      ? { initialSession: restored.session, initialEvents: restored.events as never }
      : {}),
    // host 留空 = 同源 /eve/v1/*。原生外壳里由 WKWebView 的拦截转到部署环境，
    // 开发时由 Vite 代理转到本地 Eve。两边都不需要给 Eve 配 CORS。
    ...(context.eveOrigin ? { host: context.eveOrigin } : {}),
    headers: () => ({ authorization: `Bearer ${context.token}` }),
    adapters: { attachments: attachmentAdapter },
    prepareSend: (input) =>
      withTurnContext(input, {
        page: pageRef.current,
        images: imagesContext(numberImages(imagesRef.current)),
      }),
  });
  runtimeRef.current = runtime;

  // 首页「拍报告」：打开时入口里带着一张图，放进输入框，用户补一句话再发。只放一次。
  const attachedRef = useRef(false);
  useEffect(() => {
    if (entry.mode !== "new" || !entry.attachImage || attachedRef.current || restored) return;
    const dataUrl = entry.attachImage;
    const timer = window.setTimeout(() => {
      attachedRef.current = true;
      void runtime.thread.composer.addAttachment(dataUrlToFile(dataUrl, "photo.jpg"));
    }, 0);
    return () => window.clearTimeout(timer);
  }, [entry, runtime, restored]);

  // 原生也可以在对话已打开时塞进一张图。
  useEffect(() => {
    window.__aimAttachImage__ = (dataUrl: string) => {
      void runtime.thread.composer.addAttachment(dataUrlToFile(dataUrl, "photo.jpg"));
    };
    return () => {
      delete window.__aimAttachImage__;
    };
  }, [runtime]);

  // 「让 Agent 分析当前记录」：打开就把问题发出去。只发一次——
  // 票据轮换等原因重渲染时不能再发。
  //
  // 推到下一拍再发，并在 cleanup 里取消：挂载后立刻卸载（开发时 StrictMode 必然如此）
  // 会让适配器以「运行时已卸载」为由静默丢掉这次发送，而「已发送」标记却已经立起来了。
  const autoSentRef = useRef(false);
  useEffect(() => {
    if (entry.mode !== "new" || !entry.autoSend || autoSentRef.current || restored) return;
    const text = entry.autoSend;
    const timer = window.setTimeout(() => {
      autoSentRef.current = true;
      void runtime.thread.append({ role: "user", content: [{ type: "text", text }] });
    }, 0);
    return () => window.clearTimeout(timer);
  }, [entry, runtime, restored]);

  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <BizDataProvider context={context}>
        <ApprovalBridge context={context} runtime={runtime}>
          <NewConversationBridge accountKey={accountKeyFromToken(context.token)} />
          <HistoryBridge onOpen={() => setHistoryOpen(true)} />
          <TurnFinishedBridge />
          <AppearBridge
            enabled={entry.mode === "resume"}
            accountKey={accountKeyFromToken(context.token)}
            runtime={runtime}
            onSwitch={onAppearSwitch}
          />
          <SessionRecovery onDiscardStoredSession={onDiscardStoredSession} />
          <ToolRenderers />
          <Thread
            chip={page ? <ContextChip page={page} onClear={() => setPage(null)} /> : undefined}
            attachmentError={attachmentError}
          />
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
      </BizDataProvider>
    </AssistantRuntimeProvider>
  );
};

export const App = () => {
  const [context, setContext] = useState<NativeContext | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [restored, setRestored] = useState<Restored | null>(null);
  const [restoring, setRestoring] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const entry = useMemo(() => (context ? resolveEntry(context) : null), [context]);

  // 拿到会话票之后、开始渲染对话之前，把上一段对话的事件取回来。
  // `initialEvents` 只在运行时创建那一刻生效，所以必须先取完再渲染。
  useEffect(() => {
    // 快捷入口开的是新的一段，不接回上一段。
    if (!context || entry?.mode !== "resume") return;
    const stored = loadSession(accountKeyFromToken(context.token));
    if (!stored) return;
    let cancelled = false;
    setRestoring(true);
    void fetchSessionEvents(stored.sessionId, context.token, context.eveOrigin)
      .then((snapshot) => {
        if (cancelled) return;
        // 一条都没取到就当新对话开始：那段会话可能已经被服务端清掉了。
        if (!snapshot || snapshot.events.length === 0) return;
        setRestored({
          session: { sessionId: stored.sessionId, streamIndex: snapshot.nextIndex },
          events: snapshot.events,
        });
      })
      .finally(() => {
        if (!cancelled) setRestoring(false);
      });
    return () => {
      cancelled = true;
    };
  }, [context, entry?.mode]);

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
      .then((snapshot) => {
        if (!snapshot || snapshot.events.length === 0) {
          // 运行时升级会让旧会话的事件日志读不回来（CORRUPTED_EVENT_LOG）。
          // 目录里还留着条目，内容却没了——说清楚，别把用户丢在一个空白页面上猜。
          setNotice("这段对话的内容已不可用，可能是服务升级导致的。你可以开一段新的。");
          return;
        }
        setRestored({
          session: { sessionId: picked.eveSessionId, streamIndex: snapshot.nextIndex },
          events: snapshot.events,
        });
        saveSession(accountKeyFromToken(context.token), {
          sessionId: picked.eveSessionId,
          streamIndex: snapshot.nextIndex,
        });
        if (picked.id) void touchSession(context.token, picked.id, context.eveOrigin);
      })
      .finally(() => setRestoring(false));
  };

  /** 从快捷入口回到标签页时，切到最近那段（快捷入口会把它存成最近一段）。 */
  const followLatestStored = (eveSessionId: string) => {
    // 目录 id 不知道；只影响「顶到最前」，切换本身按 Eve 会话 id 进行。
    switchToSession({ id: "", eveSessionId } as AgentSessionSummary);
  };

  if (error) return <div className="fatal">{error}</div>;
  if (!context || !entry) return <div className="loading">正在准备…</div>;
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
        entry={entry}
        restored={restored}
        onSwitch={switchToSession}
        onAppearSwitch={followLatestStored}
        onDiscardStoredSession={() => {
          clearSession(accountKeyFromToken(context.token));
          setRestored(null);
        }}
      />
    </div>
  );
};

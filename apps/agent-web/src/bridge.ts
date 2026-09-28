/**
 * 与原生外壳之间的桥。
 *
 * Web 侧**不做登录**：会话票由原生注入。原生已经持有它，让 WebView 再登一次意味着
 * 密码要在两处出现，而且两边的过期时机会不一致。
 *
 * 桥是单向为主：原生 → Web 用启动时注入的全局对象，Web → 原生用
 * `webkit.messageHandlers`。没有原生外壳时（浏览器里开发）走 dev 回退。
 */

import type { WriteKind } from "./turnWrites";

export interface PageContext {
  title: string;
  summary: string;
}

/**
 * 这次对话面是从哪里打开的。
 *
 * - resume：AIM 标签页，接回上一段。
 * - new：快捷入口，开一段新的；带 pageContext 时输入框上方显示「正在看：…」，
 *   带 autoSend 时打开就把这句话发出去（「让 Agent 分析当前记录」）。
 */
export type AgentEntry =
  | { mode: "resume" }
  | { mode: "new"; pageContext?: PageContext; autoSend?: string };

export interface NativeContext {
  /** `aim.v1.…` 会话票。 */
  token: string;
  /** 跟随原生的浅色/深色。 */
  theme: "light" | "dark";
  /** Eve 的来源。原生里是部署环境，开发时留空走同源代理。 */
  eveOrigin?: string;
  /** 当前家庭与孕期。卡片凭 ID 去公开 API 取真实标题和称呼，不采信模型参数。 */
  familyId?: string;
  pregnancyId?: string;
  /** 缺省按 resume 处理。 */
  entry?: AgentEntry;
}

type MessageHandler = { postMessage: (body: unknown) => void };

declare global {
  interface Window {
    /** 原生在页面加载前注入。 */
    __AIM_NATIVE__?: NativeContext;
    /** 原生在票据轮换后调用，Web 侧重新取一次。 */
    __aimOnContextChanged__?: (next: NativeContext) => void;
    /** 原生工具栏的「开新对话」。由 Web 侧注册，原生只负责调用。 */
    __aimNewConversation__?: () => void;
    /** 原生工具栏的「历史对话」。面板在 Web 侧渲染——切换会话要重建运行时。 */
    __aimOpenHistory__?: () => void;
    /** 原生标签页重新出现时调用：若快捷入口里开了新的一段，切过去。 */
    __aimOnAppear__?: () => void;
    webkit?: { messageHandlers?: Record<string, MessageHandler | undefined> };
  }
}

export const hasNativeShell = (): boolean =>
  typeof window !== "undefined" && window.__AIM_NATIVE__ !== undefined;

/**
 * 让原生把用户带到 App 里的某一页。
 *
 * 流里的条目点开后应当落到原生页面，而不是在 WebView 里再画一遍——资料库和记录
 * 已经有原生实现，重画一份意味着两处要同步维护，而且返回手势会错乱。
 */
export const openNative = (route: { kind: "record" | "task" | "knowledge"; id: string }): void => {
  const handler = window.webkit?.messageHandlers?.aimNavigate;
  if (!handler) {
    console.warn("[aim] 没有原生外壳，忽略跳转", route);
    return;
  }
  handler.postMessage(route);
};

/** 告诉原生这一轮写了哪几类东西，原生据此只刷新受影响的页面。 */
export const notifyTurnFinished = (kinds: readonly WriteKind[]): void => {
  window.webkit?.messageHandlers?.aimTurnFinished?.postMessage({ kinds });
};

/**
 * 开发回退：浏览器里没有原生外壳时，用 Vite 代理登一次拿票。
 *
 * 只在 `import.meta.env.DEV` 下编译进来，生产产物里不含账号逻辑。
 */
const devFallbackContext = async (): Promise<NativeContext> => {
  const phone = import.meta.env.VITE_AIM_DEV_PHONE;
  const password = import.meta.env.VITE_AIM_DEV_PASSWORD;
  if (!phone || !password) {
    throw new Error(
      "开发环境缺少 VITE_AIM_DEV_PHONE / VITE_AIM_DEV_PASSWORD，" +
        "在 apps/agent-web/.env.local 里配置（该文件不进版本库）",
    );
  }
  const response = await fetch("/api/v1/auth/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ phone, password }),
  });
  if (!response.ok) {
    throw new Error(`开发登录失败：HTTP ${response.status}`);
  }
  const { token, family_id, pregnancy_id } = (await response.json()) as {
    token: string;
    family_id?: string;
    pregnancy_id?: string | null;
  };
  return { token, theme: "light", familyId: family_id, pregnancyId: pregnancy_id ?? undefined };
};

/**
 * 从会话票里取出账号标识，只用于给本地存储分键。
 *
 * 不做验签——那是服务端的事，客户端验了也不增加任何安全性。这里要的只是
 * 「换账号后不要把上一个账号的对话接回来」这一个性质。
 * 取不到就退回一个固定键：宁可所有账号共用一段历史被覆盖，也不能因为解析失败
 * 就把不同账号的对话混在同一个键上。
 */
export const accountKeyFromToken = (token: string): string => {
  const parts = token.split(".");
  if (parts.length !== 4) return "unknown";
  try {
    const padded = parts[2] + "=".repeat((4 - (parts[2].length % 4)) % 4);
    const payload: unknown = JSON.parse(
      atob(padded.replace(/-/g, "+").replace(/_/g, "/")),
    );
    const accountId = (payload as { account_id?: unknown })?.account_id;
    return typeof accountId === "string" ? accountId : "unknown";
  } catch {
    return "unknown";
  }
};

export const loadNativeContext = async (): Promise<NativeContext> => {
  const injected = window.__AIM_NATIVE__;
  if (injected) return injected;
  if (import.meta.env.DEV) return devFallbackContext();
  throw new Error("缺少原生注入的会话票");
};

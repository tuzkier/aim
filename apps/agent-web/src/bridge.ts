/**
 * 与原生外壳之间的桥。
 *
 * Web 侧**不做登录**：会话票由原生注入。原生已经持有它，让 WebView 再登一次意味着
 * 密码要在两处出现，而且两边的过期时机会不一致。
 *
 * 桥是单向为主：原生 → Web 用启动时注入的全局对象，Web → 原生用
 * `webkit.messageHandlers`。没有原生外壳时（浏览器里开发）走 dev 回退。
 */

export interface NativeContext {
  /** `aim.v1.…` 会话票。 */
  token: string;
  /** 跟随原生的浅色/深色。 */
  theme: "light" | "dark";
  /** Eve 的来源。原生里是部署环境，开发时留空走同源代理。 */
  eveOrigin?: string;
}

type MessageHandler = { postMessage: (body: unknown) => void };

declare global {
  interface Window {
    /** 原生在页面加载前注入。 */
    __AIM_NATIVE__?: NativeContext;
    /** 原生在票据轮换后调用，Web 侧重新取一次。 */
    __aimOnContextChanged__?: (next: NativeContext) => void;
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

/** 告诉原生这一轮结束了，可以刷新受影响的页面。 */
export const notifyTurnFinished = (): void => {
  window.webkit?.messageHandlers?.aimTurnFinished?.postMessage({});
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
  const { token } = (await response.json()) as { token: string };
  return { token, theme: "light" };
};

export const loadNativeContext = async (): Promise<NativeContext> => {
  const injected = window.__AIM_NATIVE__;
  if (injected) return injected;
  if (import.meta.env.DEV) return devFallbackContext();
  throw new Error("缺少原生注入的会话票");
};

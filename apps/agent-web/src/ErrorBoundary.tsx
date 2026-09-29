import { Component, type ErrorInfo, type ReactNode } from "react";
import { reportToNative } from "./bridge";

/**
 * 渲染出错时的兜底。
 *
 * 没有它时，任何一张卡片渲染抛错，React 会把整棵树卸掉，WebView 里只剩一片白——
 * 用户看到的就是「AIM 莫名其妙变空白」，而且没有任何办法恢复。
 */
export class ErrorBoundary extends Component<
  { fallback: (retry: () => void) => ReactNode; scope: string; children: ReactNode },
  { error: Error | null }
> {
  state: { error: Error | null } = { error: null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    reportToNative("render-error", {
      scope: this.props.scope,
      message: error.message,
      stack: (info.componentStack ?? "").slice(0, 1500),
    });
  }

  render() {
    if (this.state.error) return this.props.fallback(() => this.setState({ error: null }));
    return this.props.children;
  }
}

/** 整个对话面挂了：给一句人话和一个重新加载的入口。 */
export const PageFallback = () => (
  <div className="fatal" role="alert">
    <p>对话面出了点问题。</p>
    <button type="button" className="btn btn--primary" onClick={() => window.location.reload()}>
      重新加载
    </button>
  </div>
);

/** 单条消息画不出来：只丢这一条，不连累整段对话。 */
export const MessageFallback = () => (
  <p className="tool-card__status tool-card__status--error">这条消息显示不了。</p>
);

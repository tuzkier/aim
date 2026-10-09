import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { reportToNative } from "./bridge";
import { ErrorBoundary, PageFallback } from "./ErrorBoundary";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ErrorBoundary scope="page" fallback={() => <PageFallback />}>
      <App />
    </ErrorBoundary>
  </StrictMode>,
);

// 渲染之外的异常（事件回调、未处理的 Promise）不会进错误边界，单独记下来。
window.addEventListener("error", (event) =>
  reportToNative("window-error", { message: String(event.message) }),
);
window.addEventListener("unhandledrejection", (event) =>
  reportToNative("unhandled-rejection", { message: String(event.reason?.message ?? event.reason) }),
);

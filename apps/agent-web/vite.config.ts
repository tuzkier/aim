import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// 走 Vite 代理而不是直连，是为了让浏览器把 Eve 当同源：
// eve 客户端默认就打同源的 /eve/v1/*，同时也免了给 Eve 配 CORS。
export default defineConfig({
  // 产物从 App bundle 经自定义 scheme 加载，资源路径必须是相对的。
  base: "./",
  plugins: [react()],
  server: {
    proxy: {
      "/eve": { target: "http://127.0.0.1:2210", changeOrigin: true },
      "/api": { target: "http://127.0.0.1:8100", changeOrigin: true },
    },
  },
});

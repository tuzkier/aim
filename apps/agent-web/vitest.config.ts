import { defineConfig } from "vitest/config";

// 只测纯逻辑（入口解析、攒批、事件归纳、文案）。组件测试放到第三期。
export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});

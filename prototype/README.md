# 孕期 AI Agent App 可交互原型

这是用于验证首期产品闭环的移动端高保真原型，不是正式 iOS 工程，也不连接后端或 Eve Runtime。

## 已覆盖的产品闭环

1. 创建家庭身份和孕期档案；
2. 生成 Today 与未来四周计划；
3. 查看、完成和分配任务；
4. 向 Agent 提供新情况；
5. Agent 更新同一份计划；
6. 家庭成员看到同步结果并接收邀请。

## 本地运行

```bash
npm ci --prefer-offline --no-audit --no-fund
npm run dev -- --host 0.0.0.0 --port 4173 --strictPort
```

## 验证

```bash
npm run check:runtime
npm run test:runtime
npm run build
```

视觉基准在 `reference/today-selected-concept.png`，最终设计对照结论在 `design-qa.md`。

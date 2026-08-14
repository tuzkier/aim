# ADR-0004：统一 Agent Runtime 与 Tool Gateway

## 状态

已接受

## 背景

产品包含多个专业 Agent，但不能让它们各自维护数据、直接修改计划或向用户输出互相冲突的结论。

## 决策

所有 Agent 运行在统一 Runtime。成长规划 Agent 负责调度和统一方案，专业 Agent 提供领域判断，所有业务修改通过 Tool Gateway 执行。

## 影响

- 多 Agent 共用上下文、权限、Tools 和任务状态；
- 每件事只有一个主责 Agent；
- Tool 需要定义输入、确认、幂等、重试和撤销；
- Runtime 成为核心系统，需要重点测试。

## 备选方案

- 各 Agent 独立运行：容易各说各话并造成数据冲突；
- 单一全能 Agent：难以形成明确专业职责和可测试 Skills。

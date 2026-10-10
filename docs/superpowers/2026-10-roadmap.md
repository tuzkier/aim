# 2026-10 产品路线图与进度

用户要求（2026-10-10）：全景图里的方向全部做完，持续推进、不逐步等确认；产品与医学口径由 Claude 按推荐默认决定并写进各自规格。推送到 GitHub 需用户明确同意。

每个子项目都走：设计规格 → 实施计划 → 子代理逐任务实现与审查 → 整分支审查 → 合并回本地 `development`。
功能分支从 `development` 开；子代理不指定 model 参数（本机 model 别名会 404）。

## 进度

| # | 子项目 | 状态 | 规格 / 计划 |
|---|---|---|---|
| 0 | 资料库 2.0 第 1 期：孕期百科 | ✅ 已合并 development | specs/2026-10-09-library-2-design.md、plans/2026-10-09-library-2-phase1-encyclopedia.md |
| 0 | 胎动计数 | ✅ 已合并 development（e608582） | specs/2026-10-09-fetal-movement-design.md、plans/2026-10-09-fetal-movement.md |
| 1 | 胎动收尾：Agent 对 under / reported_less 用「现在」；计数页显示时跳过过期断点收尾 | ✅ 已合并 development | 遗留：指令里「慢一倍」仍按 latest or today's，与 under 只看今天不一致（下次动 Agent 指令时顺手统一） |
| 2 | 补缺口：孕期待办 4–42 周（31 条新模板）；危险信号 19 条三档；孕周推进自动续任务；AIM 读危险信号；iOS 三档自查与血压急症横幅 | ✅ 已合并 development | specs/2026-10-10-fill-gaps-design.md、plans/2026-10-10-fill-gaps.md |
| 3 | 资料库第 2 期：AIM 翻目录（list_library / get_library_entry）与引用渲染、原生跳转、各资料页问 AIM 上下文 | ✅ 已合并 development（真实模型端到端通过） | plans/2026-10-10-library-2-phase2-aim-citations.md |
| 4 | 资料库第 3 期：档案可编辑、产检报告结构与表单/详情、create_checkup_report 与预览卡、本周关注新规则 | ✅ 已完成并合并本地 development（文字输入的真实模型端到端通过） | plans/2026-10-10-library-2-phase3-reports.md、reports/2026-10-10-library-2-phase3-validation.md |
| 5 | 资料库第 4 期：AIM 记得的事（memory 类型、remember / forget_memory、当轮读取注入、记忆页） | ✅ 已完成并合并本地 development（真实模型 UI 通过） | plans/2026-10-10-library-2-phase4-memory.md、reports/2026-10-10-library-2-phase4-validation.md |
| 6 | 主动提醒（本地通知版）：每日胎动、产检/待办到期、每周简报、通知偏好与免打扰、点通知跳转 | ✅ 已完成并合并本地 development（系统送达、冷启动点击与退出撤销通过） | specs/2026-10-10-ios-local-reminders-design.md、plans/2026-10-10-ios-local-reminders.md、reports/2026-10-10-ios-local-reminders-validation.md |
| 7 | 分娩模式：宫缩计时（5-1-1）、待产包核对入口、「我们去医院了」（家庭动态 + App 内提醒） | 待做 | — |
| 8 | 情绪关照：每日心情、EPDS 自评（孕晚期、产后 2/6 周）、高分时引导求助（含 12356） | 待做 | — |
| 9 | 产后延续：记录分娩切换产后阶段、宝宝档案、喂养/尿布/睡眠记录、产后 42 天复查、疫苗与证件清单 | 待做 | — |

## 当前接续点（2026-10-10）

- Claude 停在资料库第 3 期任务 6；Codex 已接续完成表单、详情与提醒，并跑通任务 7。验收报告明确记录了照片识别旅程的未验证范围。
- 第 5 项「AIM 记得的事」已完成：手动管理、AIM 记住/撤销/确认遗忘、当轮读取、私有隔离与家庭容量限制均已验收。
- 第 6 项「主动提醒」已完成：未来 28 天本地计划、设置与免打扰、业务变化重排、旧 scope 清理，以及系统真实通知冷启动均已验证。模拟器构建已采用本地签名以覆盖 Keychain。
- 下一主线是第 7 项「分娩模式」，之后是情绪关照、产后延续。
- 继承用户最新排序要求：先做主线任务；零散小尾巴、推送与发布收尾集中到后面处理。

## 部署约束（上线前必须满足）

- **后端（含新危险信号三档内容）部署前，含三档自查的 iOS 构建必须先上 TestFlight，并确认在用设备已更新。** 旧版 App 会把 same_day 条目的结论显示成「记下来，下次产检时告诉医生」，与条目自己的 action（今天或明天联系）矛盾。服务端无法区分新旧客户端。
- 生产库迁移会新建 `plan_template_seeds` 并回填；本地开发库已手工把 `template_id` 改为 varchar(160)（早先跑过 100 的旧版 0012）。
- 已知时区问题：服务端孕周按 UTC 日期算，北京时间 0–8 点跨周时最多晚 8 小时；后续统一时钟函数时处理。
- 百科与待办、危险信号的就医措辞在 2026-10-10 多轮修订后只经 AI 审核，上线前建议产科医生复核 `content/README.md` 中「待产科医生复核」清单。

## 已定的跨项目决定

- 远程推送（APNs）需要用户的 Apple 开发者证书与服务器密钥，暂不接；提醒一律先用 iOS 本地通知。
  需要「通知家人」的场景（如「我们去医院了」）先落为家庭动态 + 家人打开 App 时的醒目提示。
- 医学内容一律离线起草、对照权威指南自审，文案集中放常量或 content/ 便于复核；AI 审核不替代临床医生。
- 新记录类型复用 records 表；旧版 App 把未知类型解码为 unknown，不会崩。

## 待处理的小尾巴（不阻塞，择机顺手做）

- web `citations.ts` 的 `PENDING` 编号部分收紧为只容忍两侧空白（现在段末坏标记会藏掉到段尾的正文）；`RecordStoreTests` 注释「网页端只认小写」不准确。
- 模拟器会弹系统「使用强密码？」「保存密码？」，挡住 UI 测试的注册步骤——在 UI 测试里处理系统弹窗（interruption monitor 或关闭密码自动填充）。
- 本地后端在保存孕期信息时偶发 500（一次 UI 回归中出现），待查。
- Agent 目录每次约 5K token：中期可把「编号｜标题｜别名」紧凑索引放进系统指令做缓存前缀。

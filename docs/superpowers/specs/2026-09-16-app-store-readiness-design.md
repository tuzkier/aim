# App Store 上架前工程准备 设计规格

## 1. 目标

把 iOS 客户端和后端补到 App Store 审核能通过的最低要求：账号注销、隐私政策与用户协议、隐私清单、医疗免责声明、版本号与出口合规声明。并把上架前仍需人工完成的事项（域名 + HTTPS、ICP 备案、App Store Connect 元数据）写成清单放进部署文档，不在本次代码范围内解决。

## 2. 已确认的决策

- **注销采用「停用 30 天再删」**：申请即停用、不能登录；30 天内重新登录自动撤销注销；到期由后台脚本真正删除。
- **运营主体为个人开发者「王韩斌」**，联系邮箱 `whb4d12@gmail.com`。文案里主体和邮箱各只出现在一处常量，将来换公司只改那里。
- **注册防滥用只依赖现有网关限流**（生产 nginx 对 `/api/v1/auth/` 已限 5 次/分钟），短信验证码另立项目。
- **ATS 例外暂时保留**：生产后端仍是裸 IP + 明文 HTTP，`NSAllowsArbitraryLoads` 现在删掉 App 就连不上。它是上架前的硬性阻塞项，记入清单，等域名 + HTTPS 配好后删除。

## 3. 账号注销

### 3.1 状态机

`accounts.status` 现为 `String(20)`，取值 `active` / `disabled`。新增 `pending_deletion`，并新增列 `deletion_requested_at timestamptz null`（迁移 `0008_account_deletion`）。

```
active ──申请注销──▶ pending_deletion ──30 天后 purge──▶ （行删除）
   ▲                      │
   └────30 天内登录────────┘
```

### 3.2 接口

| 接口 | 行为 |
| --- | --- |
| `POST /api/v1/auth/deletion-request` | 需 Bearer；body `{ "password": "…" }`，密码错返回 401（与登录同一失败文案）。成功后 `status = pending_deletion`、`deletion_requested_at = now()`，返回 204。已是 `pending_deletion` 时幂等返回 204。 |
| `POST /api/v1/auth/login` | 账号为 `pending_deletion` 且在 30 天内：把状态改回 `active`、清空 `deletion_requested_at`，正常发 token，响应体新增字段 `deletion_cancelled: true`（其它情况为 `false`）。超过 30 天但尚未 purge 的账号按不存在处理（401，同一失败文案）。`disabled` 账号同样 401。 |
| 所有需要认证的接口 | `platform/auth` 的认证依赖在验签后按 `account_id` 查一次账号状态，非 `active` 返回 401。这一查询是主键查找，每请求一次可接受。 |

契约：`contracts/public-api/openapi.json` 通过 `make contracts` 重新生成，iOS `Generated/OpenAPI/Models.swift` 同步。

### 3.3 定时清理脚本

`services/api/scripts/purge_deleted_accounts.py`，与现有 `reset_password.py` 同风格，用同一套配置连库。逻辑放在应用层用例 `PurgeExpiredDeletions`，脚本只是入口，便于测试。

对每个 `status = pending_deletion` 且 `deletion_requested_at <= now() - 30 天` 的账号：

1. 删除其 `agent_sessions`（外键已 CASCADE）。
2. 删除其发出的 `family_invitations`（`invited_by` 为 RESTRICT，必须先删）；`accepted_account_id` 已 SET NULL。
3. 对其所在的每个家庭：
   - 若家庭还有其它**已加入**（active）成员：`tasks.assigned_member_id = NULL`（该账号的）；他的 `visibility = private` 记录删除（没有别人能看，保留无意义）；`family` 记录保留；若 `families.created_by` 是该账号，改为加入时间最早的其它成员；`records.author_account_id`、`pregnancies.created_by`、`pregnancy_facts.recorded_by_account_id`、`task_changes.changed_by_actor_id` 这些无外键的审计字段**保留原 UUID**——客户端只用它判断「能否编辑」，从不展示作者，保留即等价于匿名。
   - 若该账号是家庭唯一成员：删除该家庭的 pregnancies、pregnancy_facts、records、plans、tasks、task_changes、family_invitations，再删家庭本身。
4. 删除 `family_members`（CASCADE）与 `accounts` 行。

脚本输出每个账号的处理摘要（账号 id、删了几个家庭、匿名了几个），支持 `--dry-run`。部署文档加一行 crontab（每天一次）。

### 3.4 iOS

- `FamilyView` 新增分组「账号」，四行：`隐私政策`、`用户协议`（打开 §4 的页面）、`退出登录`、`注销账号`。退出登录调现有 `AppSessionStore.clear()`。
- 注销：点击后 `confirmationDialog` 说明「30 天内重新登录可撤销，之后数据将被删除」，确认后弹 sheet 要求输入密码，调 `deletion-request`；成功后 `session.clear()` 回到登录页并显示一条提示「注销申请已提交，30 天内登录可撤销」；失败在 sheet 内显示错误，提交中按钮 loading。
- 登录响应 `deletion_cancelled == true` 时，进入主界面后显示一次 toast「欢迎回来，注销申请已取消」。
- `BusinessRepositoryProtocol` 新增 `requestAccountDeletion(password:)`；登录返回的 `SessionResponse` 增加 `deletionCancelled: Bool`（解码缺省 false，兼容旧响应）。

## 4. 隐私政策与用户协议

### 4.1 内容与位置

两份中文静态页面，源文件在 `apps/legal/privacy.html` 与 `apps/legal/terms.html`，纯 HTML + 内联样式，无外链脚本。主体与邮箱来自页面顶部的两个占位常量。

隐私政策必须覆盖：收集的数据（手机号、密码哈希、家庭成员称呼与角色、孕期日期、健康记录、待办、与 AIM 的对话内容）、用途（提供孕期计划与家庭协作、AI 建议）、存储（服务器位于中国大陆，密码 argon2id 加密）、家庭内共享规则（同一家庭成员可见记录）、第三方（AI 模型服务商处理对话内容、不用于广告、不出售）、用户权利（查看、修改、删除记录；注销账号 30 天机制）、未成年人（不面向 14 岁以下）、联系方式、更新日期。

用户协议必须覆盖：服务描述、账号责任、**医疗免责声明**（不替代医生诊断与治疗，紧急情况立即就医）、内容规范、服务变更与终止、争议解决。

### 4.2 提供方式

- 生产 nginx（`infrastructure/deploy/nginx-aim.conf`）新增 `location /legal/ { alias /opt/aim/legal/; }`，本地 `nginx-local.conf` 同样，compose 挂载 `apps/legal`。`deploy.sh` 在上传前端产物之后同样把 `apps/legal` 上传到 `/opt/aim/legal`。
- URL 固定为 `<网关>/legal/privacy.html` 与 `<网关>/legal/terms.html`。iOS 端通过 `AgentWebScheme` 同一套网关地址推导（新增 `legalURL(_:)`），用 `SFSafariViewController` 打开。
- App Store Connect 的隐私政策 URL 填生产地址；域名配好后地址随之变化，页面内容不变。

### 4.3 注册时同意

`OnboardingView` 注册模式下按钮上方增加一行 `Toggle`：「我已阅读并同意《用户协议》和《隐私政策》」，两个书名号可点开对应页面。未勾选时注册按钮禁用；登录模式不显示。`AuthForm` 的可提交判定纳入该状态，单元测试覆盖。UI 测试的 `registerNewAccount` 助手补上勾选步骤。

## 5. 医疗免责声明

`AgentView` 头部副标题改为常驻两行：第一行沿用「孕期里的事，说一声就好」，第二行 `footnote` 灰字「AIM 的建议不能替代医生诊断，紧急情况请立即就医」。不做首次启动弹窗——注册时已同意含免责条款的协议，Agent 界面又常驻提示，审核备注里说明这两处即可。

## 6. iOS 打包元数据

| 项 | 值 |
| --- | --- |
| `MARKETING_VERSION` | `1.0.0`（AimApp 目标 Debug/Release 显式写入） |
| `CURRENT_PROJECT_VERSION` | 保持 `1`；每次上传递增，写进部署文档 |
| `Info.plist` | 新增 `ITSAppUsesNonExemptEncryption = false` |
| `PrivacyInfo.xcprivacy` | 新建于 `Resources/`，加入 App 目标资源。`NSPrivacyTracking = false`；`NSPrivacyTrackingDomains` 空；收集数据类型：手机号（关联身份、用途 App 功能）、用户 ID（同上）、健康数据（关联、App 功能）、其它用户内容（关联、App 功能）；必要原因 API：`NSPrivacyAccessedAPICategoryUserDefaults` 原因 `CA92.1` |
| ATS | 保留 `NSAllowsArbitraryLoads`，见 §2 |

## 7. 上架前人工清单

写入 `infrastructure/deploy/README.md` 新章节「上架前清单」：

1. 域名 + HTTPS（证书、nginx 443、`AIM_REMOTE_BASE_URL` 改 https），然后删除 `Info.plist` 的 `NSAllowsArbitraryLoads`。
2. ICP 备案（域名备案 + App 备案，主体与开发者账号一致）。
3. Apple Developer Program 付费账号，工程 `DEVELOPMENT_TEAM` 换成该团队。
4. 部署 `purge_deleted_accounts.py` 的每日 crontab。
5. App Store Connect：隐私政策 URL 填 `https://<域名>/legal/privacy.html`，隐私标签按 §6 的清单勾选，审核备注附测试账号与 §5 两处免责声明位置。
6. 每次上传前递增 `CURRENT_PROJECT_VERSION`。

## 8. 测试

- API（pytest，`services/api/tests/integration/identity/`）：申请注销后 token 被拒；登录自动撤销并返回 `deletion_cancelled: true`；超过 30 天登录 401；密码错 401；`PurgeExpiredDeletions` 对「有其它成员」与「唯一成员」两种家庭的处理，以及未到期账号不动；`--dry-run` 不写库。
- 契约测试随 `make contracts` 更新。
- iOS 单元测试：`AuthForm` 未勾选同意不可提交、登录模式不受影响；`SessionResponse` 缺少 `deletion_cancelled` 字段时解码为 false；`AgentWebScheme.legalURL` 拼接。
- iOS UI 测试：`registerNewAccount` 勾选同意；新增用例：家庭页「注销账号」→ 输入密码 → 回到登录页 → 用同一账号登录 → 看到「注销申请已取消」。

## 9. 不在本次范围

- 短信验证码注册。
- 域名、证书、ICP 备案、开发者账号等人工事项（§7 只写清单）。
- App Store 截图与文案。
- 家庭其它成员在注销 30 天窗口内看到「注销中」标记。

## 10. 验收标准

1. 注销申请后旧 token 立即失效，30 天内登录恢复并提示，30 天后脚本删除且家庭数据按 §3.3 处理。
2. 两份法律页面在本地网关与生产网关均可访问，注册页与家庭页能打开。
3. 未勾选同意无法注册；UI 测试全绿（既有两条与 Agent WebView 相关的失败除外）。
4. Agent 界面常驻免责声明。
5. 工程含 `PrivacyInfo.xcprivacy`、`ITSAppUsesNonExemptEncryption`、`MARKETING_VERSION`，Archive 无隐私清单相关警告。
6. 部署文档含上架前清单与 crontab。

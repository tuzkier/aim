# 2026-10-12 生产发布记录

用户授权发布，并明确确认在用手机全部安装 TestFlight **1.0.0（202610121442）**，随后完成后端与网页上线。

## 发布版本

- 生产源码：`db2d8c1b2da3159d73b87528b8d436bf5537b537`。主体功能为 `eb1cbfc`，发布准备为 `bc9e68c`，本次补入产后内容路由修复 `db2d8c1`。
- GitHub development 已从 `56be775` 推送到该源码提交；之后的发布记录提交不改变应用代码。
- API、Eve、网页和法律页已部署；生产数据库从 **0011 → 0012 → 0013**，模板种子回填通过。
- 新镜像保留先前完成构建的依赖层，API 覆盖最终提交的完整 `src`；Eve 代码与已构建版本一致。最终镜像先在隔离数据库中运行完整接口冒烟，再按标准 aim 项目和原有生产环境变量启动，未变更密钥或数据卷。
- API 镜像：`sha256:78d259e895b61046022624bd4abd55742a178c3caf8e7568fa491248d45a150f`。
- Eve 镜像：`sha256:b078219b20c3e66a416df482f97a358f6ee15bf32c367688526e9e7662f3a8a7`。
- 两份镜像标注 revision `db2d8c1`；服务器 `/opt/aim/app/DEPLOYED_REVISION` 记录完整源码 SHA。

## 发布前演练与修复

- 保存数据库、代码、法律页与网页、Nginx、附件和 Eve 工作流副本，旧 API/Eve 镜像保留回退标签；切换前另做即时数据库备份。
- 将生产备份恢复到仅内部可访问的临时演练数据库，迁移后孕期、任务、记录数量保持不变，回填数量与既有模板去重数一致。
- 演练发现通用 `/content/{collection}` 先匹配了 `/content/postpartum`，导致 404；调整路由注册顺序并补集成回归，API **556 passed**、Agent **62 passed / 3 skipped**、lint、契约和结构检查通过。契约 JSON 仅排序变化，语义内容相同。
- 最终生产镜像的隔离接口检查通过：三个内容地址、出生 14/42 天、宝宝档案、私密喂养、编辑、删除、已有事实拒绝撤回、首页读取。演练数据只写入临时数据库，结束后已删除该库。

## 线上验证

- API、Eve、PostgreSQL 均 running / healthy；Alembic 为 `0013_postpartum_babies (head)`。
- 网关、API、对话面、隐私政策、用户协议、产后清单、孕周及待产准备内容均返回 **200**。
- Eve 无票访问、伪造身份头访问均返回 **401**。
- `AIM_DEPLOYMENT=production`、`EVE_USE_MOCK_MODEL=0`、`AIM_AGENT_MODEL=deepseek-flash`，模型密钥存在；没有打印密钥。
- 切换前后生产孕期、待办和记录数量完全相同；模板回填校验通过。
- 从开发机访问公网同样通过；对话页引用的 JS 与 CSS 均可加载。旧的带 hash 静态资源保留，避免已打开页面请求旧资源失败。
- 切换后的检查窗口内 API 日志没有出现 500 或 Traceback。没有用真实生产账号制造测试记录或读取其私密内容。

## 运行产物与回退

- `/tmp/aim-production-route-verify.log`：556 项 API 与其余回归。
- `/tmp/aim-production-final-rehearsal.log`：最终镜像隔离冒烟。
- `/tmp/aim-production-deploy-db2d8c1.log`、`/tmp/aim-production-live-verification.log`、`/tmp/aim-production-external-verification.log`：切换、内网与公网验证。
- 服务器备份：`/opt/aim/backups/release-20261012-bc9e68c/`；目录仅 root 可访问，含即时 `database-at-switch.dump`、原代码、网页、Nginx、附件与工作流。
- 原代码、网页和法律页分别保存在 `/opt/aim/app-before-db2d8c1`、`web-before-db2d8c1`、`legal-before-db2d8c1`；旧镜像使用 `rollback-20261012-bc9e68c` 标签。
- 本次没有执行数据库回退。若新版本使用后需要回退，先核对新增事实，不能盲目恢复旧数据库覆盖用户的新记录。

## 验证边界

生产验证为健康、鉴权、静态页面、内容接口、版本与迁移核对；写入路径在同一最终镜像的隔离演练库验证。真机最终用户操作未由代理逐项重跑。既有 Eve 跨版本旧会话兼容边界与 HTTP/HTTPS 状态仍见部署说明；本次保留了完整工作流和旧镜像副本，不宣称所有旧会话均可重放。专业医学复核与历史未复现问题继续保留在已有验收记录里。

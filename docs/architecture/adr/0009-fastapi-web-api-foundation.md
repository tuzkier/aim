# ADR-0009：使用 FastAPI 作为 Web/API 技术底座

## 状态

已接受；Agent 流式接口部分由 [ADR-0013](0013-eve-native-stream-and-tool-contract.md) 修正

## 后续修正

FastAPI 继续作为业务 Web/API 底座，但不再提供或代理 Agent SSE。iOS 直接使用 Eve 原生可恢复 NDJSON HTTP Stream。详见 ADR-0013。

## 背景

首期客户端为原生 iOS，服务端由一名开发者配合 Coding Agent 建设和维护，服务端语言确定为 Python。系统需要提供类型明确的业务 API和自动生成的 OpenAPI 契约。同时，业务规则和工具执行不能依赖具体 Web 框架；Agent 编排与会话流由独立的 Eve Runtime 承担。

## 决策

使用 FastAPI 作为服务端 Web/API 技术底座，运行于 ASGI 应用服务器之上。

FastAPI 负责：

- HTTP/JSON API；
- 请求与响应的数据校验；
- OpenAPI 契约生成；
- 身份认证入口和请求级依赖注入；
- Eve 调用业务能力所需的 Internal Tool API。

领域业务、Internal Tool API 和数据访问分别置于独立模块。路由层只完成协议转换、鉴权入口和用例调用，不承载核心业务规则。Agent Runtime 独立部署，通过受控 Tool API 调用与用户 API 相同的应用用例。

## 影响

### 正面

- 与 Python Agent 代码使用同一语言，减少跨语言维护成本；
- Pydantic 类型模型与 OpenAPI 便于生成和校验 iOS API 契约；
- ASGI 原生适配异步 I/O；
- 框架轻量，适合按清晰模块边界逐步建设。

### 负面

- 用户、权限、运营后台和业务管理能力需要显式建设或选用独立组件；
- 若缺少模块约束，路由、ORM 与领域规则容易混杂；
- 异步接口不能代替后台任务系统，误用会阻塞 API 进程。

### 中性

- FastAPI 是接入层而非系统架构中心；未来替换接入框架不应改写核心领域模型。

## 备选方案

- Django + Django Ninja：内置 ORM、认证和 Admin 更完整，但用户明确选择 FastAPI；其一体化优势不足以覆盖这一产品对 Python Agent、异步接入和轻量边界的偏好。
- Django REST Framework：生态成熟，但样板和框架概念更多，且不作为当前选定路线。
- 直接使用 Starlette：控制力更高，但需要自行补充更多 API 校验、依赖注入和 OpenAPI 能力。

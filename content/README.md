# content

`content/` 是版本化内容目录：孕期任务、安全规则、杭州资料、营养、孕周内容（weekly）、待产准备（preparation）与孕期百科等都以文件形式放在这里，随代码一起评审和部署。

## 孕期待办模板（content/pregnancy-tasks）

孕周推进时，`initial_plan_items(week)` 按 `applicability.gestational_weeks` 把对应文件的条目放进用户的待办，格式见
`content/pregnancy-tasks/schema.json`。每条都应是孕妇这一周真能去做的一件具体的事：标题 ≤20 字，摘要 ≤60 字；
检查写指南常见孕周并注明「按医生安排」；杭州政策类只写去哪里查、准备什么，不写金额和天数；
与百科对应的任务，标题措辞尽量和百科条目一致；数胎动一律按「数到 10 次」、
「2 小时内不足 10 次或比平时明显少就联系医院」写，和 `body.fetal-movement` 保持一致。

| 文件 | 孕周 | `id` 前缀 |
| --- | --- | --- |
| `week-04.yaml` | 4 | `w04-` |
| `week-05-12.yaml` | 5–12 | `early-`（旧文件） |
| `week-13-17.yaml` | 13–17 | `w13-` |
| `week-18.yaml` | 18–19 | 无前缀（旧文件） |
| `week-20-24.yaml` | 20–24 | `w20-` |
| `week-25-28.yaml` | 25–28 | `w25-` |
| `week-29-32.yaml` | 29–32 | `w29-` |
| `week-33-36.yaml` | 33–36 | `w33-` |
| `week-37-40.yaml` | 37–40 | `w37-` |
| `week-41-42.yaml` | 41–42 | `w41-` |

- **旧文件 id 不得修改**：`week-05-12.yaml` 和 `week-18.yaml` 的条目已经写进用户的计划，`id` 作为 `source_id` 使用，
  改了会让已有待办对不上模板。需要调整措辞时只改 `title`/`summary`，不要改 `id`，也不要删条目。
- 新条目 `id` 用「文件前缀 + 短名」，全局唯一。
- `services/api/tests/contract/content/test_content_schema.py` 守住 schema、`id` 全局唯一、第 4–42 周每周都有模板，以及标题和摘要长度。

### 审核记录

- **2026-10-10，AI 自审（Claude）**：新增 8 个文件共 30 条，逐条对照《孕前和孕期保健指南（2018）》
  《中国居民膳食指南（2022）》孕期部分和本目录百科条目核对孕周与措辞。自审中修改：
  `w33-labor-signs` 补上「不足 37 周就规律宫缩也直接去医院」；`w04-avoid-risks` 补上「正在吃的药也别自己停」；
  `w13-screening` 补上「做过的还要不要再做，按医生安排」，避免已做过早唐或无创的人被催着再约；
  `w41-admission-or-induction` 改为和 `birth.overdue` 一致的「指南建议 41 周后住院引产，具体时机按医生安排」。
  **AI 审核不能替代临床医生**：上线前建议请产科医生过目，重点看检查孕周和就医指征相关条目。

## 孕期百科（content/encyclopedia）

每个主题一个文件，格式见 `content/encyclopedia/schema.json`（不在 `content/` 根目录）。新内容一律 `review_status: draft`，只在本地栈
（`AIM_CONTENT_INCLUDE_DRAFTS=1`）可见；生产在 `compose.prod.yaml` 显式关闭草稿。
审核通过后把文件改为 `review_status: reviewed` 并填写 `reviewed_at`，提交即可随下次部署上线。
`services/api/tests/contract/content/test_encyclopedia_content.py` 守住格式、链接与孕周覆盖。

### 审核清单

翻 `review_status: reviewed` 之前逐条核对：

- **首次发布的孕周覆盖**：契约测试只用「已审核」的文件检查第 4–40 周每周至少 2 条带孕周的条目。
  第一次把文件翻成 reviewed 时，这批已审核文件必须**单独**满足覆盖，否则契约测试失败、`make verify` 不过。
  截至 2026-10-09，单个文件能独立满足的只有 `body.yaml`、`diet.yaml`、`life.yaml`；
  `checkup.yaml`、`birth.yaml`、`paperwork.yaml` 都要和它们一起或在它们之后上线。
- **部署前必须跑过 `make test`**：API 启动时加载并校验百科，坏内容（重复 id、孕周不合法、政策条目缺链接等）
  会让整个 API 起不来，不只是百科打不开。
- **政策类条目（`kind: policy`）的 `ask` 只能是指路或流程型问题**，例如「产假天数去哪里查最新规定」
  「生育津贴要准备哪些材料」「出生一件事在哪里办」；不要出现求具体天数、金额或资格判断的问法，
  否则会诱导 AIM 给出结论。
- **`pick: false`**：只针对部分人群或有前提条件的条目（如羊水穿刺、控糖饮食、产后第一天）加上它，
  这些条目不进 App 首页的「这周读什么」；目录、主题页和 AIM 翻目录都照常能看到。缺省为 true。

### 审核记录

- **2026-10-09，AI 审核（Claude）**：逐条对照《孕前和孕期保健指南（2018）》《中国居民膳食指南（2022）》、
  2025 年《胎动管理专家共识》等核对了全部 61 条。已修正：胎动判断标准统一为「2 小时不足 10 次，
  或比平时明显减少（约一半）」；产检时间表孕周（中期唐筛 15–20 周、糖耐量 24–28 周）；开塞露表述；
  情绪条目补全国心理援助热线 12356；咖啡因给出「每天不超过 200 毫克」的常见建议；叶酸、补碘摘要；
  生育津贴链接改为杭州市政府门户网站的市医保局栏目（原 `ybj.hangzhou.gov.cn` 无法解析）。
  **AI 审核不能替代临床医生**：上线前建议请一位产科医生过目，重点看 `checkup`、`body` 两个文件。
- **2026-10-09，标记为 reviewed**：产品负责人确认按上述 AI 审核结果上线，六个文件全部翻为 `reviewed`。
- 仍待处理：政策条目的 `link` 多为部门首页或栏目页，有条件时换成具体办事指南页。

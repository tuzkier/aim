# content

`content/` 是版本化内容目录：孕期任务、安全规则、杭州资料、营养、孕周内容（weekly）、待产准备（preparation）与孕期百科等都以文件形式放在这里，随代码一起评审和部署。

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

翻 reviewed 前需要审核人决定或核对的遗留项：

- `diet.iodine`：摘要补一句「有甲状腺疾病的遵医嘱」。
- `checkup.schedule`：孕周表述要统一——糖耐量写的是 25–28 周，`checkup.ogtt` 是 24–28 周；
  中孕期一段「14–19 周可做中期唐筛（15–20 周）」两组孕周并列，需定一个说法。
- `diet.iron-and-folate`：摘要里「常见剂量以医生意见为准」的措辞。
- `body.fetal-movement`：数胎动的判断标准现为「2 小时不足 10 次」，国内教科书常用
  「2 小时少于 6 次或较平时减少 50%」，需定一个。
- `body.mood`：是否加心理援助热线（号码在审核时核实）。
- 四个政策条目的 `link` 目前只到部门首页，审核时尽量换成具体办事指南页。

# content

`content/` 是版本化内容目录：孕期任务、安全规则、杭州资料、营养与孕期百科都以文件形式放在这里，随代码一起评审和部署。

## 孕期百科（content/encyclopedia）

每个主题一个文件，格式见 `schema.json`。新内容一律 `review_status: draft`，只在本地栈
（`AIM_CONTENT_INCLUDE_DRAFTS=1`）可见；生产在 `compose.prod.yaml` 显式关闭草稿。
审核通过后把文件改为 `review_status: reviewed` 并填写 `reviewed_at`，提交即可随下次部署上线。
`services/api/tests/contract/content/test_encyclopedia_content.py` 守住格式、链接与孕周覆盖。

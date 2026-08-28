/**
 * 与原生保持一致的文案。
 *
 * 这些字符串在 Swift 侧也有一份（`LibraryCategoryID.title`、`FoodVerdict.displayName`、
 * `KnowledgePreview.formTitle`）。两处必须一致——同一条菜谱在对话里叫「菜谱」、
 * 在资料库里叫别的，用户会以为是两样东西。
 */

export const CATEGORY_TITLES: Record<string, string> = {
  checkups: "产检与指标",
  nutrition: "吃什么",
  symptoms: "身体感受",
  questions: "想问医生",
  paperwork: "办事指南",
  preparation: "待产准备",
  safety: "危险信号",
};

export const FORM_TITLES: Record<string, string> = {
  recipe: "菜谱",
  food_rule: "能不能吃",
  howto: "步骤",
  tip: "提示",
};

export const VERDICT_LABELS: Record<string, string> = {
  safe: "可以吃",
  limit: "可以，但要限量",
  avoid: "避免",
};

export const categoryTitle = (id: string | undefined): string =>
  (id && CATEGORY_TITLES[id]) || "资料库";

export const formTitle = (form: string | undefined): string =>
  (form && FORM_TITLES[form]) || "提示";

/** 只读工具：调用它们不改变任何事实，不该出现在「最近处理」台账里。 */
export const READ_ONLY_TOOLS = new Set([
  "get_pregnancy_context",
  "list_tasks",
  "list_records",
  "get_guidance",
  "echo_context",
  "preview_task_change",
]);

/** 步骤行上显示的中文工具名。读不到就退回原名，不猜。 */
export const TOOL_TITLES: Record<string, string> = {
  get_pregnancy_context: "查看孕期档案",
  list_tasks: "查看待办",
  list_records: "查看记录",
  get_guidance: "查阅指南",
  preview_task_change: "预演计划改动",
  echo_context: "确认当前身份范围",
  create_knowledge: "收录到资料库",
  create_task: "新建待办",
  create_record: "新建记录",
  update_task: "调整待办",
  assign_task: "分派待办",
  record_pregnancy_fact: "更新孕期信息",
  undo_operation: "撤销上一次改动",
  delete_task: "删除待办",
  delete_record: "删除记录",
};

export const toolTitle = (name: string): string => TOOL_TITLES[name] ?? name;

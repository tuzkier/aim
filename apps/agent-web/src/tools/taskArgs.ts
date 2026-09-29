/**
 * 把工具参数整理成卡片要的形状。
 *
 * 新建、完成、删除待办改成了批量；旧对话里的历史调用还是单条的形状，
 * 卡片两种都要能画出来，否则翻历史就是一片空卡。
 */

export type TaskDraft = { title: string; description?: string; dueAt?: string };

type CreateArgs = {
  tasks?: TaskDraft[];
  title?: string;
  description?: string;
  dueAt?: string;
};

export const taskDrafts = (args: CreateArgs | undefined): TaskDraft[] => {
  if (!args) return [];
  if (Array.isArray(args.tasks)) return args.tasks.filter((t) => typeof t?.title === "string");
  if (typeof args.title !== "string") return [];
  const draft: TaskDraft = { title: args.title };
  if (args.description) draft.description = args.description;
  if (args.dueAt) draft.dueAt = args.dueAt;
  return [draft];
};

export const deleteTaskIds = (args: { taskIds?: string[]; taskId?: string } | undefined): string[] =>
  Array.isArray(args?.taskIds) ? args.taskIds : args?.taskId ? [args.taskId] : [];

/**
 * 旧对话里残留的 ask_question。升级后模型已经不能再发起提问，这里只负责把历史上的
 * 问题和选项用中文摆出来，不再显示 `ask_question` 这个工具名。
 */
export const askQuestionView = (
  args: { question?: string; prompt?: string; options?: ({ label?: string } | string)[] } | undefined,
): { question: string | null; options: string[] } => ({
  question: args?.question ?? args?.prompt ?? null,
  options: (args?.options ?? [])
    .map((option) => (typeof option === "string" ? option : option?.label))
    .filter((label): label is string => typeof label === "string" && label.length > 0),
});

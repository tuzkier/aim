export type WriteKind = "task" | "record" | "knowledge";

/** 写工具影响到的原生页面。只读工具不在表里。 */
export const WRITE_KINDS: Record<string, WriteKind[]> = {
  create_task: ["task"],
  complete_task: ["task"],
  reschedule_task: ["task"],
  assign_task: ["task"],
  create_record: ["record"],
  create_knowledge: ["knowledge"],
  // 孕期信息可能改变预产期，首页的孕周与计划跟着变。
  record_pregnancy_fact: ["task"],
  // 撤销可能落在任何一类上；多刷一下比漏刷便宜。
  undo_operation: ["task", "record", "knowledge"],
};

type StreamEvent = {
  type?: string;
  data?: { result?: { kind?: string; toolName?: string; output?: { status?: string } } };
};

/**
 * 一批新到的事件里，成功完成的写工具影响到哪几类页面。
 *
 * 写一完成就报，不等整轮结束：用户看到卡片上的「已添加」就会切回首页，
 * 那时模型可能还在写收尾的话，等到轮次结束再刷新，首页就是旧的。
 * 只认 output.status === "completed"：approval_required 是「等确认」，还没写。
 */
export const writesIn = (events: readonly unknown[]): WriteKind[] => {
  const kinds = new Set<WriteKind>();
  for (const raw of events) {
    const event = raw as StreamEvent;
    if (event.type !== "action.result") continue;
    const result = event.data?.result;
    const affected = result?.toolName ? WRITE_KINDS[result.toolName] : undefined;
    if (result?.kind === "tool-result" && affected && result.output?.status === "completed") {
      for (const kind of affected) kinds.add(kind);
    }
  }
  return [...kinds];
};

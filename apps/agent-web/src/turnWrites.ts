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

const TURN_END = new Set(["turn.completed", "session.waiting", "turn.failed", "turn.cancelled"]);

type StreamEvent = {
  type?: string;
  data?: { result?: { kind?: string; toolName?: string; output?: { status?: string } } };
};

/**
 * 扫一批新到的事件：成功完成的写工具记进本轮，轮次结束时产出并清空。
 *
 * 只认 output.status === "completed"：approval_required 是「等确认」，还没写。
 */
export const scanTurnWrites = (
  events: readonly unknown[],
  state: { kinds: Set<WriteKind> },
): WriteKind[][] => {
  const finished: WriteKind[][] = [];
  for (const raw of events) {
    const event = raw as StreamEvent;
    if (event.type === "action.result") {
      const result = event.data?.result;
      const kinds = result?.toolName ? WRITE_KINDS[result.toolName] : undefined;
      if (result?.kind === "tool-result" && kinds && result.output?.status === "completed") {
        for (const kind of kinds) state.kinds.add(kind);
      }
    } else if (event.type && TURN_END.has(event.type) && state.kinds.size > 0) {
      finished.push([...state.kinds]);
      state.kinds.clear();
    }
  }
  return finished;
};

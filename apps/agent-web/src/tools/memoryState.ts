export const memoryHeadline = (result: unknown, failed = false): string => {
  if (failed) return "没有记住";
  const output = result as { status?: string } | undefined;
  return output?.status === "completed" ? "已记住" : "正在记住";
};

export const memoryOperationID = (result: unknown): string | undefined => {
  const output = result as { status?: string; operationId?: string; operation_id?: string } | undefined;
  return output?.status === "completed" ? output.operationId ?? output.operation_id : undefined;
};

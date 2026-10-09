/**
 * 攒批的判定，从 React 里拆出来好测。
 *
 * Eve 的审批批次必须整批一次回才结算，所以「所有待批项都有了决定」才发，
 * 并且同一批只发一次——流重放时组件会重新挂载、重新登记。
 */
export const nextDispatch = (
  pending: readonly string[],
  decisions: ReadonlyMap<string, { approved: boolean }>,
  dispatched: ReadonlySet<string>,
): { key: string; payload: { requestId: string; approved: boolean }[] } | null => {
  if (pending.length === 0) return null;
  if (!pending.every((id) => decisions.has(id))) return null;
  const key = [...pending].sort().join("|");
  if (dispatched.has(key)) return null;
  return {
    key,
    payload: pending.map((id) => ({ requestId: id, approved: decisions.get(id)!.approved })),
  };
};

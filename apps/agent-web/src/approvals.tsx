import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

/**
 * 审批批次的攒批与一次性回复。
 *
 * 为什么不用 `props.respondToApproval`：`@assistant-ui/eve` v0.0.14 的
 * `onRespondToToolApproval` 是 `agent.respond([一条])`，一次点击发一条。而 Eve 的
 * 批次**必须整批一次回**才结算——本地栈实测（eve 0.44.1，一轮三个审批）：
 *
 *   逐条串行回：approval.settled ×3，但 input.resolved 为 0，批次从不结算
 *   三条一次回：input.resolved ×1，批次结算
 *
 * 而且 eve 的 `respond` 在一轮进行中会 reject，适配器又把被丢的发送静默吞掉
 * （`if (!isDroppedSend(error)) throw error`）——所以界面上表现为「第一个能点，
 * 后面的点了没反应」。
 *
 * 这里的做法：每张待批卡片登记自己，用户的决定先攒在本地；等这一批全部有了决定，
 * 再走一次 HTTP 把整批送回去。`eve/react` 的 `respond` 本身就收数组，只是适配器
 * 没把这条路暴露出来，所以这一个操作绕过它直连。
 */

type Decision = { approved: boolean };

interface ApprovalBatchValue {
  /** 这一项登记自己在等待拍板。返回注销函数。 */
  register: (approvalId: string) => () => void;
  /** 一次决定整组。用户看到的是一件事，就该是一次拍板。 */
  decideAll: (approved: boolean) => void;
  /** 这一项已经有决定了。 */
  decisionOf: (approvalId: string) => Decision | undefined;
  /** 当前还等着拍板的项数。为 0 时不显示按钮。 */
  pendingCount: number;
  /** 整组已送出，正在等服务端结算。 */
  dispatching: boolean;
}

const ApprovalBatchContext = createContext<ApprovalBatchValue | null>(null);

export interface ApprovalTransport {
  /** 把整批决定送回 Eve。 */
  respondAll: (responses: { requestId: string; approved: boolean }[]) => Promise<void>;
}

export const ApprovalBatchProvider = ({
  transport,
  children,
}: {
  transport: ApprovalTransport;
  children: ReactNode;
}) => {
  const pendingRef = useRef(new Set<string>());
  const [decisions, setDecisions] = useState<Map<string, Decision>>(new Map());
  const [dispatching, setDispatching] = useState(false);
  // 已经送出过的批次，避免流重放时重复提交。
  const dispatchedRef = useRef(new Set<string>());

  const [pendingCount, setPendingCount] = useState(0);

  const register = useCallback((approvalId: string) => {
    pendingRef.current.add(approvalId);
    setPendingCount(pendingRef.current.size);
    return () => {
      pendingRef.current.delete(approvalId);
      setPendingCount(pendingRef.current.size);
    };
  }, []);

  /**
   * 一次决定当前所有待批项。
   *
   * 用户说的是「把这三道菜收进菜谱」——一件事。拆成三次拍板既不符合他的表达，
   * 也正是逐条回复、批次结算不了的来源。
   */
  const decideAll = useCallback((approved: boolean) => {
    const pending = [...pendingRef.current];
    if (pending.length === 0) return;
    setDecisions((previous) => {
      const next = new Map(previous);
      for (const id of pending) {
        if (!next.has(id)) next.set(id, { approved });
      }
      return next;
    });
  }, []);

  // 攒齐就发。放在 effect 里而不是 decide 里，是为了拿到 setState 之后的完整快照——
  // 在 decide 内部判断会用到过期的 decisions。
  useEffect(() => {
    const pending = [...pendingRef.current];
    if (pending.length === 0) return;
    if (!pending.every((id) => decisions.has(id))) return;

    const key = pending.slice().sort().join("|");
    if (dispatchedRef.current.has(key)) return;
    dispatchedRef.current.add(key);

    const payload = pending.map((id) => ({
      requestId: id,
      approved: decisions.get(id)!.approved,
    }));

    setDispatching(true);
    void transport
      .respondAll(payload)
      .catch((error: unknown) => {
        // 发送失败要允许重试，否则用户卡死在一批已决定却送不出去的卡片上。
        dispatchedRef.current.delete(key);
        console.error("[aim] 审批批次发送失败", error);
      })
      .finally(() => setDispatching(false));
  }, [decisions, transport]);

  const value = useMemo<ApprovalBatchValue>(
    () => ({
      register,
      decideAll,
      decisionOf: (approvalId) => decisions.get(approvalId),
      pendingCount,
      dispatching,
    }),
    [register, decideAll, decisions, pendingCount, dispatching],
  );

  return (
    <ApprovalBatchContext.Provider value={value}>{children}</ApprovalBatchContext.Provider>
  );
};

export const useApprovalBatch = (): ApprovalBatchValue => {
  const value = useContext(ApprovalBatchContext);
  if (!value) throw new Error("useApprovalBatch 必须在 ApprovalBatchProvider 内使用");
  return value;
};

/** 待批卡片登记自己，卸载时注销。 */
export const useRegisterApproval = (approvalId: string | undefined, awaiting: boolean) => {
  const { register } = useApprovalBatch();
  useEffect(() => {
    if (!approvalId || !awaiting) return;
    return register(approvalId);
  }, [approvalId, awaiting, register]);
};

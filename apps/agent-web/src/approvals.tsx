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
import { nextDispatch } from "./approvalBatch";

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
  /** 最近一次提交失败的说明。为空表示没有失败。 */
  error: string | null;
  /** 重新提交上一次失败的那一批。 */
  retry: () => void;
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
  const [error, setError] = useState<string | null>(null);
  // 递增它让攒批 effect 重跑一次：失败后决定仍在，但 effect 不会自己再触发。
  const [attempt, setAttempt] = useState(0);
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
    const next = nextDispatch([...pendingRef.current], decisions, dispatchedRef.current);
    if (!next) return;
    dispatchedRef.current.add(next.key);
    setError(null);
    setDispatching(true);
    void transport
      .respondAll(next.payload)
      .catch(() => {
        // 允许重试：不移除的话这一批永远不会再发，用户卡在一组已决定却送不出去的卡片上。
        dispatchedRef.current.delete(next.key);
        setError("没能提交，请检查网络后重试");
      })
      .finally(() => setDispatching(false));
  }, [decisions, transport, attempt]);

  const retry = useCallback(() => setAttempt((n) => n + 1), []);

  const value = useMemo<ApprovalBatchValue>(
    () => ({
      register,
      decideAll,
      decisionOf: (approvalId) => decisions.get(approvalId),
      pendingCount,
      dispatching,
      error,
      retry,
    }),
    [register, decideAll, decisions, pendingCount, dispatching, error, retry],
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

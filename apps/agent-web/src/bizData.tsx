import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { NativeContext } from "./bridge";

export interface PlanTask {
  id: string;
  title: string;
  status: string;
  due_at: string | null;
  scheduled_for: string | null;
  assigned_member_id: string | null;
}

export interface FamilyMember {
  account_id: string;
  role: string;
  nickname: string | null;
  status: string;
}

const ROLE_NAMES: Record<string, string> = {
  mother: "妈妈",
  father: "爸爸",
  other_caregiver: "家人",
};

export const memberName = (member: FamilyMember | undefined): string =>
  member?.nickname?.trim() || (member && ROLE_NAMES[member.role]) || "家人";

export const formatWhen = (iso: string | null | undefined): string | null => {
  if (!iso) return null;
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return null;
  return new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Shanghai",
  }).format(parsed);
};

interface BizData {
  tasks: Map<string, PlanTask>;
  members: Map<string, FamilyMember>;
  facts: Map<string, unknown>;
  reload: () => void;
}

type Snapshot = Omit<BizData, "reload">;

const EMPTY: BizData = {
  tasks: new Map(),
  members: new Map(),
  facts: new Map(),
  reload: () => {},
};
const BizDataContext = createContext<BizData>(EMPTY);

const getJson = async (context: NativeContext, path: string): Promise<unknown> => {
  const response = await fetch(`${context.eveOrigin ?? ""}${path}`, {
    headers: { authorization: `Bearer ${context.token}`, accept: "application/json" },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
};

/**
 * 卡片要显示的业务事实：待办标题与日期、家人称呼、孕期信息的当前值。
 *
 * 取不到时卡片退回显示「这项待办」之类的中性说法，不拿模型参数顶上——
 * 模型可能把标题张冠李戴，而确认卡就是让用户核对的地方。
 */
export const BizDataProvider = ({
  context,
  children,
}: {
  context: NativeContext;
  children: ReactNode;
}) => {
  const [data, setData] = useState<Snapshot>(EMPTY);
  const [version, setVersion] = useState(0);
  const reload = useCallback(() => setVersion((n) => n + 1), []);
  const { familyId, pregnancyId, token, eveOrigin } = context;

  useEffect(() => {
    if (!familyId || !pregnancyId) return;
    const scope = { token, theme: context.theme, eveOrigin };
    let cancelled = false;
    void Promise.allSettled([
      getJson(scope, `/api/v1/pregnancies/${pregnancyId}/plan`),
      getJson(scope, `/api/v1/families/${familyId}`),
      getJson(scope, `/api/v1/pregnancies/${pregnancyId}`),
    ]).then(([plan, family, pregnancy]) => {
      if (cancelled) return;
      setData((previous) => ({
        tasks:
          plan.status === "fulfilled"
            ? new Map(
                ((plan.value as { tasks?: PlanTask[] }).tasks ?? []).map((task) => [task.id, task]),
              )
            : previous.tasks,
        members:
          family.status === "fulfilled"
            ? new Map(
                ((family.value as { members?: FamilyMember[] }).members ?? []).map((member) => [
                  member.account_id,
                  member,
                ]),
              )
            : previous.members,
        facts:
          pregnancy.status === "fulfilled"
            ? new Map(
                (
                  (pregnancy.value as { facts?: { key: string; value: unknown; status: string }[] })
                    .facts ?? []
                )
                  .filter((fact) => fact.status === "active")
                  .map((fact) => [fact.key, fact.value]),
              )
            : previous.facts,
      }));
    });
    return () => {
      cancelled = true;
    };
    // theme 不影响取数，只是为了凑 NativeContext 的形状。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [familyId, pregnancyId, token, eveOrigin, version]);

  const value = useMemo(() => ({ ...data, reload }), [data, reload]);
  return <BizDataContext.Provider value={value}>{children}</BizDataContext.Provider>;
};

export const useBizData = (): BizData => useContext(BizDataContext);

/**
 * 卡片找不到自己的待办时请求一次刷新（模型可能刚新建了它）。
 * 每个 id 只请求一次，避免真不存在时反复刷。
 */
const requested = new Set<string>();
export const useEnsureTask = (taskId: string | undefined): PlanTask | undefined => {
  const { tasks, reload } = useBizData();
  const task = taskId ? tasks.get(taskId) : undefined;
  useEffect(() => {
    if (!taskId || task || requested.has(taskId)) return;
    requested.add(taskId);
    reload();
  }, [taskId, task, reload]);
  return task;
};

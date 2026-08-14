import {
  ArrowLeftIcon,
  CalendarIcon,
  CheckIcon,
  ChevronRightIcon,
  ClockIcon,
  Cross2Icon,
  HomeIcon,
  InfoCircledIcon,
  MagicWandIcon,
  PaperPlaneIcon,
  PersonIcon,
  PlusIcon,
  ReaderIcon,
  UpdateIcon,
} from "@radix-ui/react-icons";
import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
  type ReactNode,
} from "react";
import {
  BottomSheet,
  FlowStack,
  KeyboardInput,
  MobileScroll,
  useKeyboard,
  type FlowControls,
  type FlowScreen,
} from "./mobile";

type TabId = "today" | "plan" | "agent" | "family";
type TaskStatus = "todo" | "scheduled" | "done";

type Task = {
  id: string;
  title: string;
  owner: "妈妈" | "爸爸" | "共同";
  time: string;
  week: string;
  status: TaskStatus;
  priority?: boolean;
  priorityReason?: string;
  changedBy?: "Agent" | "你";
  note: string;
};

type AgentState = "idle" | "analyzing" | "review" | "applied";

type PrototypeState = {
  tasks: Task[];
  agentState: AgentState;
  agentMessage: string;
  latestInput: string;
  agentSheetOpen: boolean;
  toast: string;
  invitationSent: boolean;
  toggleTask: (id: string) => void;
  scheduleTask: (id: string) => void;
  assignTask: (id: string, owner: Task["owner"]) => void;
  delayTask: (id: string) => void;
  openAgent: () => void;
  closeAgent: () => void;
  analyzeAgentInput: (input: string) => void;
  applyAgentProposal: () => void;
  undoLastChange: () => void;
  dismissToast: () => void;
  resetJourney: () => void;
  sendInvitation: () => void;
};

const initialTasks: Task[] = [
  {
    id: "ultrasound",
    title: "预约下周的系统超声检查",
    owner: "妈妈",
    time: "今天",
    week: "本周",
    status: "todo",
    priority: true,
    priorityReason: "系统超声有检查时间窗口，今天预约更容易选到合适时间。",
    note: "建议今天完成预约，并提前准备医保电子凭证和上次产检资料。",
  },
  {
    id: "walk",
    title: "晚饭后散步 20 分钟",
    owner: "妈妈",
    time: "19:30",
    week: "本周",
    status: "todo",
    note: "以身体舒适为准；如有医生限制，请遵循医生建议。",
  },
  {
    id: "records",
    title: "整理上次产检资料",
    owner: "爸爸",
    time: "20:30",
    week: "本周",
    status: "todo",
    note: "把检查单、报告和医生交代放到同一处，方便下次就诊。",
  },
  {
    id: "materials",
    title: "核对检查所需材料",
    owner: "爸爸",
    time: "8月18日",
    week: "下周",
    status: "todo",
    priorityReason: "检查日期确定后，需要提前核对证件和既往资料。",
    note: "核对预约凭证、身份证件、医保凭证和既往检查资料。",
  },
  {
    id: "questions",
    title: "整理要问医生的 3 个问题",
    owner: "共同",
    time: "8月19日",
    week: "下周",
    status: "todo",
    note: "把近期变化和最关心的问题提前整理，减少就诊时遗漏。",
  },
  {
    id: "benefits",
    title: "确认杭州生育待遇材料",
    owner: "爸爸",
    time: "8月28日",
    week: "第 3 周",
    status: "todo",
    note: "先核对适用条件和材料清单，不确定的信息以官方渠道为准。",
  },
];

const AppStateContext = createContext<PrototypeState | null>(null);

function usePrototypeState() {
  const state = useContext(AppStateContext);
  if (!state) throw new Error("usePrototypeState must be used inside AppStateProvider");
  return state;
}

function AppStateProvider({ children }: PropsWithChildren) {
  const [tasks, setTasks] = useState(initialTasks);
  const [agentState, setAgentState] = useState<AgentState>("idle");
  const [agentMessage, setAgentMessage] = useState("今天的计划已准备好");
  const [latestInput, setLatestInput] = useState("");
  const [agentSheetOpen, setAgentSheetOpen] = useState(false);
  const [previousTasks, setPreviousTasks] = useState<Task[] | null>(null);
  const [toast, setToast] = useState("");
  const [invitationSent, setInvitationSent] = useState(false);

  useEffect(() => {
    if (agentState !== "analyzing") return;
    const timer = window.setTimeout(() => {
      setAgentMessage("已识别 1 条新情况，将影响 3 项计划");
      setAgentState("review");
    }, 760);
    return () => window.clearTimeout(timer);
  }, [agentState]);

  const value = useMemo<PrototypeState>(
    () => ({
      tasks,
      agentState,
      agentMessage,
      latestInput,
      agentSheetOpen,
      toast,
      invitationSent,
      toggleTask: (id) =>
        setTasks((current) =>
          current.map((task) =>
            task.id === id ? { ...task, status: task.status === "done" ? "todo" : "done", changedBy: "你" } : task,
          ),
        ),
      scheduleTask: (id) => {
        setTasks((current) => {
          setPreviousTasks(current);
          return current.map((task) => {
            if (task.id === id) return { ...task, status: "scheduled", time: "8月19日 09:30", priority: false, changedBy: "你" };
            if (task.id === "materials") return { ...task, week: "本周", time: "今天", priority: true, changedBy: "你" };
            return task;
          });
        });
        setToast("检查已安排，下一步已切换为核对材料");
      },
      assignTask: (id, owner) => {
        setTasks((current) => {
          setPreviousTasks(current);
          return current.map((task) => (task.id === id ? { ...task, owner, changedBy: "你" } : task));
        });
        setToast(`任务已分配给${owner}`);
      },
      delayTask: (id) => {
        setTasks((current) => {
          setPreviousTasks(current);
          return current.map((task) =>
            task.id === id ? { ...task, time: "明天", priority: false, changedBy: "你" } : task,
          );
        });
        setToast("任务已调整到明天");
      },
      openAgent: () => setAgentSheetOpen(true),
      closeAgent: () => setAgentSheetOpen(false),
      analyzeAgentInput: (input) => {
        const normalized = input.trim() || "医生把检查改到下周三了";
        setLatestInput(normalized);
        setAgentMessage("正在理解这项变化…");
        setAgentState("analyzing");
      },
      applyAgentProposal: () => {
        setTasks((current) => {
          setPreviousTasks(current);
          return current.map((task) => {
            if (task.id === "ultrasound") {
              return { ...task, time: "8月19日", note: "医生把检查改到下周三，具体预约时间仍待确认。", changedBy: "Agent" };
            }
            if (task.id === "materials") {
              return { ...task, week: "本周", time: "8月18日", changedBy: "Agent" };
            }
            if (task.id === "records") return { ...task, owner: "爸爸", changedBy: "Agent" };
            return task;
          });
        });
        setAgentState("applied");
        setAgentMessage("3 项变更已应用到家庭计划");
        setAgentSheetOpen(false);
        setToast("Agent 已应用 3 项变更");
      },
      undoLastChange: () => {
        if (!previousTasks) return;
        setTasks(previousTasks);
        setPreviousTasks(null);
        setToast("刚才的变更已撤销");
        setAgentState("idle");
        setAgentMessage("今天的计划已准备好");
      },
      dismissToast: () => setToast(""),
      resetJourney: () => {
        setTasks(initialTasks);
        setAgentState("idle");
        setAgentMessage("今天的计划已准备好");
        setLatestInput("");
        setAgentSheetOpen(false);
        setPreviousTasks(null);
        setToast("");
      },
      sendInvitation: () => setInvitationSent(true),
    }),
    [agentMessage, agentSheetOpen, agentState, invitationSent, latestInput, previousTasks, tasks, toast],
  );

  return <AppStateContext.Provider value={value}>{children}</AppStateContext.Provider>;
}

const tabMeta: Array<{ id: TabId; label: string; icon: ReactNode }> = [
  { id: "today", label: "今天", icon: <CalendarIcon /> },
  { id: "plan", label: "计划", icon: <ReaderIcon /> },
  { id: "agent", label: "Agent", icon: <MagicWandIcon /> },
  { id: "family", label: "家庭", icon: <HomeIcon /> },
];

function screenForTab(tab: TabId): FlowScreen {
  const common = {
    id: tab,
    footer: (flow: FlowControls) => <TabBar active={tab} flow={flow} />,
    footerHeight: 78,
  };

  if (tab === "plan") return { ...common, render: (flow) => <PlanScreen flow={flow} /> };
  if (tab === "agent") return { ...common, render: (flow) => <AgentScreen flow={flow} /> };
  if (tab === "family") return { ...common, render: (flow) => <FamilyScreen flow={flow} /> };
  return { ...common, render: (flow) => <TodayScreen flow={flow} /> };
}

function TabBar({ active, flow }: { active: TabId; flow: FlowControls }) {
  const keyboard = useKeyboard();
  return (
    <nav className="tab-bar" aria-label="主导航">
      {tabMeta.map((tab) => (
        <button
          className="tab-item"
          data-active={active === tab.id}
          key={tab.id}
          onClick={() => {
            keyboard.hide();
            if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
            if (active !== tab.id) flow.replace(screenForTab(tab.id));
          }}
          aria-label={tab.label}
          aria-current={active === tab.id ? "page" : undefined}
          data-testid={`tab-${tab.id}`}
        >
          <span className="tab-icon">{tab.icon}</span>
          <span>{tab.label}</span>
        </button>
      ))}
    </nav>
  );
}

function HeaderAgentButton() {
  const { openAgent, agentState } = usePrototypeState();
  return (
    <button className="header-agent-button" onClick={openAgent} aria-label="告诉 Agent 新情况" data-state={agentState}>
      <MagicWandIcon />
    </button>
  );
}

function TodayScreen({ flow }: { flow: FlowControls }) {
  const { tasks, agentMessage, agentState, toggleTask, openAgent } = usePrototypeState();
  const actionable = tasks.filter((task) => task.status === "todo");
  const priority = actionable.find((task) => task.priority) ?? actionable[0];
  const upcoming = actionable.filter((task) => task.id !== priority?.id).slice(0, 2);

  return (
    <MobileScroll key={priority?.id ?? "all-done"} className="app-screen warm-screen">
      <main className="screen-content root-screen today-screen" data-testid="today-screen">
        <header className="large-title-header">
          <div className="title-toolbar"><h1>今天</h1><HeaderAgentButton /></div>
          <div className="date-context">
            <CalendarIcon />
            <span>8月14日 周五</span>
            <span className="date-dot">·</span>
            <span>孕18周 + 3天</span>
          </div>
        </header>

        {priority ? (
          <button
            className="priority-panel"
            onClick={() => flow.push(taskDetailScreen(priority.id))}
            data-testid="priority-task"
          >
            <span className="eyebrow">今天最重要</span>
            <strong>{priority.title}</strong>
            <span className="priority-reason"><InfoCircledIcon />{priority.priorityReason ?? "根据当前时间和家庭计划，建议优先处理。"}</span>
            <span className="primary-button">{priority.id === "ultrasound" ? "去安排" : "开始处理"}</span>
          </button>
        ) : (
          <div className="priority-panel all-done-panel"><span className="ready-check"><CheckIcon /></span><strong>今天的重要事项已完成</strong><span>Agent 会继续关注下一阶段变化。</span></div>
        )}

        <section className="section-block">
          <h2>接下来</h2>
          <div className="grouped-list task-list">
            {upcoming.map((task) => (
              <TaskRow
                task={task}
                key={task.id}
                onToggle={() => toggleTask(task.id)}
                onOpen={() => flow.push(taskDetailScreen(task.id))}
              />
            ))}
          </div>
        </section>

        <button className="agent-status-row" onClick={() => agentState === "applied" ? flow.push(changeDetailScreen()) : openAgent()} data-testid="agent-status">
          <MagicWandIcon />
          <span className="agent-status-copy">
            <strong>{agentState === "review" ? "有 3 项变更等待确认" : agentState === "analyzing" ? "Agent 正在理解新情况" : "Agent"}</strong>
            <span>{agentMessage}</span>
          </span>
          {agentState === "analyzing" ? <span className="native-spinner" aria-label="处理中" /> : <span>{agentState === "review" ? "确认" : "查看"}</span>}
          {agentState !== "analyzing" ? <ChevronRightIcon /> : null}
        </button>
      </main>
    </MobileScroll>
  );
}

function TaskRow({ task, onToggle, onOpen }: { task: Task; onToggle: () => void; onOpen: () => void }) {
  const settled = task.status !== "todo";
  return (
    <div className="task-row" data-done={settled} data-status={task.status} data-testid={`task-${task.id}`}>
      <button className="check-control" onClick={onToggle} aria-label={task.status === "done" ? `恢复 ${task.title}` : `完成 ${task.title}`}>
        {settled ? <CheckIcon /> : null}
      </button>
      <button className="task-row-main" onClick={onOpen}>
        <span className="task-title">{task.title}</span>
        <span className="task-meta">{task.owner}{task.time !== "今天" ? ` · ${task.time}` : ""}{task.changedBy ? ` · ${task.changedBy}调整` : ""}</span>
      </button>
      <ChevronRightIcon className="row-chevron" />
    </div>
  );
}

function PlanScreen({ flow }: { flow: FlowControls }) {
  const { tasks, toggleTask } = usePrototypeState();
  const groups = ["本周", "下周", "第 3 周", "第 4 周"];

  return (
    <MobileScroll className="app-screen warm-screen">
      <main className="screen-content root-screen plan-screen" data-testid="plan-screen">
        <header className="large-title-header compact-header">
          <div className="title-toolbar"><div><span className="eyebrow accent-eyebrow">孕18周 + 3天</span><h1>未来四周</h1></div><HeaderAgentButton /></div>
          <p>一份会随真实情况持续调整的家庭计划。</p>
        </header>

        <div className="week-rail" aria-label="四周计划进度">
          {[18, 19, 20, 21].map((week, index) => (
            <div className="week-node" data-active={index === 0} key={week}>
              <span>{week}周</span>
              <i />
            </div>
          ))}
        </div>

        <div className="plan-groups">
          {groups.map((group) => {
            const groupTasks = tasks.filter((task) => task.week === group);
            return (
              <section className="plan-group" key={group}>
                <header>
                  <h2>{group}</h2>
                  <span>{groupTasks.length || (group === "第 4 周" ? 1 : 0)} 项</span>
                </header>
                <div className="grouped-list">
                  {groupTasks.length ? (
                    groupTasks.map((task) => (
                      <TaskRow
                        task={task}
                        key={task.id}
                        onToggle={() => toggleTask(task.id)}
                        onOpen={() => flow.push(taskDetailScreen(task.id))}
                      />
                    ))
                  ) : (
                    <button className="empty-plan-row" onClick={() => flow.push(agentSuggestionScreen())}>
                      <PlusIcon />
                      <span>让 Agent 补充阶段准备</span>
                      <ChevronRightIcon />
                    </button>
                  )}
                </div>
              </section>
            );
          })}
        </div>
      </main>
    </MobileScroll>
  );
}

function AgentScreen({ flow }: { flow: FlowControls }) {
  const { agentState, agentMessage, latestInput, openAgent, applyAgentProposal } = usePrototypeState();
  const stateTitle = agentState === "review" ? "有 3 项变更等待确认" : agentState === "analyzing" ? "正在理解新情况" : agentState === "applied" ? "最近一次变更已应用" : "家庭计划运行正常";

  return (
    <MobileScroll className="app-screen warm-screen">
      <main className="screen-content root-screen agent-screen" data-testid="agent-screen">
        <header className="large-title-header compact-header">
          <span className="agent-kicker"><MagicWandIcon /> 成长规划 Agent</span>
          <div className="title-toolbar"><h1>工作台</h1><HeaderAgentButton /></div>
          <p>查看 Agent 正在做什么、准备改什么，以及哪些事情需要你决定。</p>
        </header>

        <section className="agent-work-card" data-state={agentState}>
          <div className="agent-work-heading">
            <span className="agent-glyph"><MagicWandIcon /></span>
            <div>
              <strong>{stateTitle}</strong>
              <span>{agentMessage}</span>
            </div>
          </div>
          {agentState === "analyzing" ? <progress max="100" value="62" aria-label="理解进度" /> : null}
          {agentState === "review" ? (
            <button className="secondary-action" onClick={openAgent}>查看并确认变更 <ChevronRightIcon /></button>
          ) : agentState === "applied" ? (
            <button className="secondary-action" onClick={() => flow.push(changeDetailScreen())}>查看具体变更 <ChevronRightIcon /></button>
          ) : null}
        </section>

        <button className="agent-primary-entry" onClick={openAgent} data-testid="agent-open">
          <span><MagicWandIcon /></span><span><strong>告诉 Agent 新情况</strong><small>检查改期、医生交代、身体变化…</small></span><ChevronRightIcon />
        </button>

        <section className="section-block guardrail-section">
          <h2>Agent 如何工作</h2>
          <div className="grouped-list guardrail-list">
            <div><span>1</span><p><strong>先理解</strong><small>把你的描述整理成明确事实</small></p></div>
            <div><span>2</span><p><strong>再预览</strong><small>列出准备修改的计划与分工</small></p></div>
            <div><span>3</span><p><strong>你确认后执行</strong><small>普通变更可随时撤销</small></p></div>
          </div>
        </section>

        <section className="section-block recent-agent-section">
          <h2>最近处理</h2>
          <div className="grouped-list compact-list">
            <button className="history-row" onClick={() => flow.push(changeDetailScreen())}>
              <span className="history-icon"><CheckIcon /></span>
              <span><strong>建立孕18周计划</strong><small>今天 09:08 · 你已确认</small></span>
              <ChevronRightIcon />
            </button>
            {latestInput ? (
              <div className="history-row latest-history">
                <span className="history-icon"><ClockIcon /></span>
                <span><strong>{latestInput}</strong><small>{agentState === "review" ? "等待你确认" : agentState === "applied" ? "已应用" : "正在理解"}</small></span>
                {agentState === "review" ? <button className="inline-confirm" onClick={applyAgentProposal}>确认</button> : null}
              </div>
            ) : null}
          </div>
        </section>
      </main>
    </MobileScroll>
  );
}

function FamilyScreen({ flow }: { flow: FlowControls }) {
  const { invitationSent, sendInvitation, tasks } = usePrototypeState();
  const [inviteOpen, setInviteOpen] = useState(false);
  const momOpen = tasks.filter((task) => task.owner === "妈妈" && task.status === "todo").length;
  const dadOpen = tasks.filter((task) => task.owner === "爸爸" && task.status === "todo").length;

  return (
    <>
      <MobileScroll className="app-screen warm-screen">
        <main className="screen-content root-screen family-screen" data-testid="family-screen">
          <header className="large-title-header compact-header">
            <div className="title-toolbar"><h1>我们的家庭</h1><HeaderAgentButton /></div>
            <p>每个人使用自己的账号，共同维护一份孕期计划。</p>
          </header>

          <section className="family-summary">
            <div className="family-mark"><HomeIcon /></div>
            <div><strong>小满家庭</strong><span>孕18周 + 3天 · 杭州</span></div>
          </section>

          <section className="section-block">
            <div className="section-title-row"><h2>家庭成员</h2><span>{invitationSent ? 3 : 2} 人</span></div>
            <div className="grouped-list member-list">
              <div className="member-row">
                <span className="member-avatar">林</span>
                <span><strong>林小满</strong><small>妈妈 · {momOpen} 项待办</small></span>
                <span className="member-state">本人</span>
              </div>
              <div className="member-row">
                <span className="member-avatar sage-avatar">周</span>
                <span><strong>周屿</strong><small>爸爸 · {dadOpen} 项待办</small></span>
                <span className="member-state online-state">已加入</span>
              </div>
              {invitationSent ? (
                <div className="member-row">
                  <span className="member-avatar waiting-avatar">陈</span>
                  <span><strong>陈阿姨</strong><small>其他照护者 · 暂无任务</small></span>
                  <span className="member-state waiting-state">等待加入</span>
                </div>
              ) : null}
            </div>
          </section>

          <button className="native-list-action" onClick={() => setInviteOpen(true)} data-testid="invite-family">
            <PlusIcon /><span>邀请家庭成员</span><ChevronRightIcon />
          </button>

          <section className="section-block family-setup-section">
            <h2>家庭资料</h2>
            <button className="native-list-action inset-action" onClick={() => flow.push(pregnancyProfileScreen())} data-testid="pregnancy-profile">
              <ReaderIcon /><span>孕期档案与杭州信息</span><ChevronRightIcon />
            </button>
          </section>
        </main>
      </MobileScroll>

      <BottomSheet
        open={inviteOpen}
        onOpenChange={setInviteOpen}
        title={invitationSent ? "邀请已发送" : "邀请加入小满家庭"}
        description={invitationSent ? "对方注册或登录后即可加入共同计划。" : "家庭成员使用自己的账号加入，你可以随时调整权限。"}
        snap={0.47}
      >
        <div className="invite-sheet-content">
          {invitationSent ? (
            <div className="sheet-success">
              <span><CheckIcon /></span>
              <strong>已发送给 138 **** 2026</strong>
              <p>邀请 24 小时内有效</p>
              <button className="sheet-primary-button" onClick={() => setInviteOpen(false)}>完成</button>
            </div>
          ) : (
            <>
              <label className="sheet-field"><span>手机号</span><span className="sheet-field-value">138 **** 2026</span></label>
              <label className="sheet-field"><span>家庭身份</span><span className="sheet-field-value">其他照护者 <ChevronRightIcon /></span></label>
              <button className="sheet-primary-button" onClick={sendInvitation}>发送邀请</button>
            </>
          )}
        </div>
      </BottomSheet>
    </>
  );
}

function GlobalAgentSheet() {
  const {
    agentSheetOpen,
    closeAgent,
    agentState,
    agentMessage,
    analyzeAgentInput,
    applyAgentProposal,
  } = usePrototypeState();
  const keyboard = useKeyboard();
  const [input, setInput] = useState("");

  const submit = () => {
    keyboard.hide();
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    analyzeAgentInput(input);
  };

  const isReview = agentState === "review";

  return (
    <BottomSheet
      open={agentSheetOpen}
      onOpenChange={(open) => { if (!open) closeAgent(); }}
      title={isReview ? "确认计划变更" : agentState === "analyzing" ? "正在理解" : "告诉 Agent 新情况"}
      description={isReview ? "先确认 Agent 理解正确，再决定是否写入家庭计划。" : "Agent 会先给出理解和变更预览，不会直接修改。"}
      snap={isReview ? 0.82 : 0.58}
    >
      <div className="agent-sheet" data-testid="agent-sheet">
        {agentState === "analyzing" ? (
          <div className="agent-analyzing"><span className="native-spinner" /><strong>正在识别时间、任务和家庭分工</strong><p>{agentMessage}</p></div>
        ) : isReview ? (
          <div className="agent-review" data-testid="agent-review">
            <section>
              <span className="review-label">我理解的是</span>
              <strong>医生把系统超声检查改到下周三</strong>
              <p>这是日程变化，不涉及新的医疗判断。</p>
            </section>
            <section>
              <span className="review-label">计划将这样变化</span>
              <div className="change-preview-list">
                <div><CalendarIcon /><span><strong>检查日期</strong><small>今天 → 8月19日（具体时间待确认）</small></span></div>
                <div><UpdateIcon /><span><strong>材料准备</strong><small>提前到 8月18日</small></span></div>
                <div><PersonIcon /><span><strong>家庭分工</strong><small>资料整理继续由爸爸负责</small></span></div>
              </div>
            </section>
            <div className="review-boundary"><InfoCircledIcon /><span>Agent 只会修改以上普通计划，不会替你预约或作医疗决定。</span></div>
            <button className="sheet-primary-button" onClick={applyAgentProposal} data-testid="apply-agent-changes">应用 3 项变更</button>
            <button className="sheet-secondary-button" onClick={closeAgent}>暂不修改</button>
          </div>
        ) : (
          <>
            <div className="agent-sheet-examples">
              <button onClick={() => setInput("医生把检查改到下周三了")}>医生把检查改到下周三了</button>
              <button onClick={() => setInput("这两天比较累，把非必要任务减少一些")}>这两天比较累，减少非必要任务</button>
            </div>
            <div className="sheet-composer">
              <KeyboardInput
                value={input}
                onChange={(event) => setInput(event.target.value)}
                onBlur={() => keyboard.hide()}
                placeholder="描述刚刚发生的变化…"
                aria-label="描述新情况"
                data-testid="agent-sheet-input"
              />
              <button onClick={submit} disabled={!input.trim()} aria-label="发送给 Agent" data-testid="agent-sheet-send"><PaperPlaneIcon /></button>
            </div>
          </>
        )}
      </div>
    </BottomSheet>
  );
}

function AppToast() {
  const { toast, undoLastChange, dismissToast } = usePrototypeState();
  if (!toast) return null;
  return (
    <div className="app-toast" role="status" data-testid="app-toast">
      <CheckIcon /><span>{toast}</span><button onClick={undoLastChange}>撤销</button><button className="toast-close" onClick={dismissToast} aria-label="关闭"><Cross2Icon /></button>
    </div>
  );
}

function detailHeader(title: string) {
  return (flow: FlowControls) => (
    <div className="native-nav-bar">
      <button onClick={flow.pop} aria-label="返回"><ArrowLeftIcon /><span>返回</span></button>
      <strong>{title}</strong>
      <span className="nav-placeholder" />
    </div>
  );
}

function taskDetailScreen(taskId: string): FlowScreen {
  return {
    id: `task-${taskId}`,
    header: detailHeader("任务详情"),
    headerHeight: 48,
    footer: (flow) => <TaskDetailFooter taskId={taskId} flow={flow} />,
    footerHeight: 86,
    render: (flow) => <TaskDetailScreen taskId={taskId} flow={flow} />,
  };
}

function TaskDetailScreen({ taskId }: { taskId: string; flow: FlowControls }) {
  const { tasks, assignTask, delayTask } = usePrototypeState();
  const [sheet, setSheet] = useState<"owner" | "time" | null>(null);
  const task = tasks.find((item) => item.id === taskId) ?? tasks[0];
  return (
    <>
      <MobileScroll className="app-screen warm-screen">
       <main className="screen-content detail-screen task-detail" data-testid="task-detail-screen">
        <span className="detail-status">{task.status === "done" ? "已完成" : task.status === "scheduled" ? "已安排" : task.priority ? "今天优先" : task.time}</span>
        <h1>{task.title}</h1>
        <p className="detail-lead">{task.note}</p>

        <section className="detail-group">
          <h2>安排</h2>
          <div className="grouped-list detail-list">
            <button onClick={() => setSheet("time")}><CalendarIcon /><span><small>时间</small><strong>{task.time}</strong></span><ChevronRightIcon /></button>
            <button onClick={() => setSheet("owner")}><PersonIcon /><span><small>负责人</small><strong>{task.owner}</strong></span><ChevronRightIcon /></button>
          </div>
        </section>

        <section className="detail-group">
          <h2>准备事项</h2>
          <div className="grouped-list checklist">
            {["确认医院可预约时间", "准备医保电子凭证", "带上上次产检资料"].map((item) => (
              <div key={item}><span className="mini-check" /><span>{item}</span></div>
            ))}
          </div>
        </section>

        <div className="provenance-note"><MagicWandIcon /><span><strong>{task.changedBy ? `${task.changedBy}最近调整` : "成长规划 Agent 创建"}</strong><small>依据当前孕周和家庭计划，可在变更记录中查看。</small></span></div>
        <div className="safety-note"><strong>说明</strong><p>具体检查时间和医疗安排以医生及医疗机构要求为准。</p></div>
       </main>
      </MobileScroll>
      <BottomSheet open={sheet === "owner"} onOpenChange={(open) => !open && setSheet(null)} title="重新分配" description="家庭成员会立即在自己的计划中看到变化。" snap={0.45}>
        <div className="option-sheet-list">
          {(["妈妈", "爸爸", "共同"] as Task["owner"][]).map((owner) => <button key={owner} onClick={() => { assignTask(task.id, owner); setSheet(null); }}><span>{owner}</span>{task.owner === owner ? <CheckIcon /> : null}</button>)}
        </div>
      </BottomSheet>
      <BottomSheet open={sheet === "time"} onOpenChange={(open) => !open && setSheet(null)} title="调整时间" description="调整后会同步到家庭计划。" snap={0.45}>
        <div className="option-sheet-list">
          <button onClick={() => setSheet(null)}><span>今天</span>{task.time === "今天" ? <CheckIcon /> : null}</button>
          <button onClick={() => { delayTask(task.id); setSheet(null); }}><span>明天</span>{task.time === "明天" ? <CheckIcon /> : null}</button>
          <button onClick={() => setSheet(null)}><span>选择日期…</span><ChevronRightIcon /></button>
        </div>
      </BottomSheet>
    </>
  );
}

function TaskDetailFooter({ taskId, flow }: { taskId: string; flow: FlowControls }) {
  const { tasks, toggleTask, scheduleTask } = usePrototypeState();
  const task = tasks.find((item) => item.id === taskId) ?? tasks[0];
  return (
    <div className="detail-footer">
      <button
        className="footer-primary"
        onClick={() => {
          if (task.id === "ultrasound" && task.status === "todo") scheduleTask(task.id);
          else toggleTask(task.id);
          flow.pop();
        }}
        data-testid="complete-task"
      >
        {task.status === "done" ? "恢复为待办" : task.id === "ultrasound" && task.status === "todo" ? "记录为已预约" : "完成任务"}
      </button>
    </div>
  );
}

function changeDetailScreen(): FlowScreen {
  return {
    id: "change-detail",
    header: detailHeader("计划变更"),
    headerHeight: 48,
    render: () => <ChangeDetailScreen />,
  };
}

function ChangeDetailScreen() {
  const { agentMessage, agentState } = usePrototypeState();
  return (
    <MobileScroll className="app-screen warm-screen">
      <main className="screen-content detail-screen change-detail" data-testid="change-detail-screen">
        <span className="agent-glyph large-agent-glyph"><MagicWandIcon /></span>
        <h1>{agentState === "analyzing" ? "正在理解变化" : agentState === "review" ? "等待你的确认" : "计划已经同步"}</h1>
        <p className="detail-lead">{agentMessage}</p>
        <section className="change-timeline">
          <div><span><CheckIcon /></span><p><strong>识别影响</strong><small>检查时间、准备材料与家庭分工</small></p></div>
          <div><span><CheckIcon /></span><p><strong>更新任务</strong><small>检查准备提前到本周</small></p></div>
          <div data-pending={agentState !== "applied"}><span>{agentState !== "applied" ? <ClockIcon /> : <CheckIcon />}</span><p><strong>同步家庭</strong><small>妈妈和爸爸看到同一份最新计划</small></p></div>
        </section>
        <div className="agent-boundary"><strong>Agent 做了什么</strong><p>本次只调整普通计划与任务，没有替你做医疗判断或预约操作。</p></div>
      </main>
    </MobileScroll>
  );
}

function agentSuggestionScreen(): FlowScreen {
  return {
    id: "agent-suggestion",
    header: detailHeader("阶段建议"),
    headerHeight: 48,
    render: () => (
      <MobileScroll className="app-screen warm-screen">
        <main className="screen-content detail-screen suggestion-screen">
          <span className="agent-glyph large-agent-glyph"><MagicWandIcon /></span>
          <h1>第 4 周先保持轻量</h1>
          <p className="detail-lead">当前没有必须提前加入的事项。Agent 会在产检结果或家庭情况变化后再调整。</p>
          <div className="safety-note"><strong>计划原则</strong><p>只在有明确依据时创建任务，避免用大量提醒制造焦虑。</p></div>
        </main>
      </MobileScroll>
    ),
  };
}

function pregnancyProfileScreen(): FlowScreen {
  return {
    id: "pregnancy-profile",
    header: detailHeader("孕期档案"),
    headerHeight: 48,
    render: () => (
      <MobileScroll className="app-screen warm-screen">
        <main className="screen-content detail-screen profile-screen" data-testid="profile-screen">
          <span className="detail-status">家庭共同档案</span>
          <h1>孕18周 + 3天</h1>
          <p className="detail-lead">用于生成计划的关键信息。修改后，Agent 会先给出计划影响预览。</p>
          <div className="form-group grouped-list profile-list">
            <button><span><small>预产期</small><strong>2027年1月11日</strong></span><ChevronRightIcon /></button>
            <button><span><small>居住城市</small><strong>浙江 · 杭州</strong></span><ChevronRightIcon /></button>
            <button><span><small>建册情况</small><strong>已建立母子健康手册</strong></span><ChevronRightIcon /></button>
            <button><span><small>常用医院</small><strong>待确认</strong></span><ChevronRightIcon /></button>
          </div>
          <div className="privacy-note"><strong>修改不会直接覆盖计划</strong><p>关键信息变化后，会先展示需要调整的任务、时间和家庭分工。</p></div>
        </main>
      </MobileScroll>
    ),
  };
}

function welcomeScreen(): FlowScreen {
  return {
    id: "welcome",
    footer: (flow) => <OnboardingFooter label="开始建立计划" onNext={() => flow.push(identityScreen())} />,
    footerHeight: 102,
    render: (flow) => <WelcomeScreen flow={flow} />,
  };
}

function WelcomeScreen({ flow }: { flow: FlowControls }) {
  return (
    <MobileScroll className="app-screen warm-screen">
      <main className="screen-content onboarding-screen" data-testid="welcome-screen">
        <button className="onboarding-close" onClick={flow.pop} aria-label="关闭"><Cross2Icon /></button>
        <span className="onboarding-step">开始之前</span>
        <h1>先建立一份<br />真正能执行的孕期计划</h1>
        <p>告诉我们当前孕周和家庭情况，Agent 会先生成今天与未来四周的行动，再逐步补全信息。</p>
        <div className="onboarding-points">
          <div><CalendarIcon /><span><strong>现在该做什么</strong><small>先处理有时间窗口的事项</small></span></div>
          <div><MagicWandIcon /><span><strong>变化后自动调整</strong><small>所有功能与 Agent 共用一份计划</small></span></div>
          <div><HomeIcon /><span><strong>全家共同完成</strong><small>独立账号、清晰分工</small></span></div>
        </div>
      </main>
    </MobileScroll>
  );
}

function identityScreen(): FlowScreen {
  return {
    id: "identity",
    header: detailHeader("家庭身份"),
    headerHeight: 48,
    footer: (flow) => <OnboardingFooter label="继续" onNext={() => flow.push(pregnancySetupScreen())} />,
    footerHeight: 102,
    render: () => <IdentityScreen />,
  };
}

function IdentityScreen() {
  const [role, setRole] = useState("妈妈");
  return (
    <MobileScroll className="app-screen warm-screen">
      <main className="screen-content onboarding-form-screen" data-testid="identity-screen">
        <span className="onboarding-step">1 / 2</span>
        <h1>你在家庭中的身份</h1>
        <p>身份只决定默认视角和分工，不代表谁拥有整个家庭账号。</p>
        <div className="selection-list">
          {["妈妈", "爸爸", "其他照护者"].map((item) => (
            <button key={item} data-selected={role === item} onClick={() => setRole(item)}>
              <span>{item}</span><span className="radio-control">{role === item ? <CheckIcon /> : null}</span>
            </button>
          ))}
        </div>
      </main>
    </MobileScroll>
  );
}

function pregnancySetupScreen(): FlowScreen {
  return {
    id: "pregnancy-setup",
    header: detailHeader("孕期信息"),
    headerHeight: 48,
    footer: (flow) => <OnboardingFooter label="生成我的计划" onNext={() => flow.push(planReadyScreen())} />,
    footerHeight: 102,
    render: () => <PregnancySetupScreen />,
  };
}

function PregnancySetupScreen() {
  return (
    <MobileScroll className="app-screen warm-screen">
      <main className="screen-content onboarding-form-screen" data-testid="pregnancy-setup-screen">
        <span className="onboarding-step">2 / 2</span>
        <h1>现在处于哪个阶段</h1>
        <p>先提供最少的信息，更多情况可以之后补充。</p>
        <div className="form-group grouped-list">
          <button><span><small>预产期</small><strong>2027年1月11日</strong></span><ChevronRightIcon /></button>
          <button><span><small>当前孕周</small><strong>孕18周 + 3天</strong></span><ChevronRightIcon /></button>
          <button><span><small>居住城市</small><strong>浙江 · 杭州</strong></span><ChevronRightIcon /></button>
        </div>
        <div className="privacy-note"><strong>你的信息由家庭掌控</strong><p>家庭成员需要通过邀请加入；Agent 只能在授权范围内调用功能。</p></div>
      </main>
    </MobileScroll>
  );
}

function planReadyScreen(): FlowScreen {
  return {
    id: "plan-ready",
    footer: (flow) => <OnboardingFooter label="进入今天" onNext={() => flow.replace(screenForTab("today"))} />,
    footerHeight: 102,
    render: () => <PlanReadyScreen />,
  };
}

function PlanReadyScreen() {
  const { resetJourney } = usePrototypeState();
  useEffect(() => resetJourney(), []);
  return (
    <MobileScroll className="app-screen warm-screen">
      <main className="screen-content onboarding-screen plan-ready-screen" data-testid="plan-ready-screen">
        <span className="ready-check"><CheckIcon /></span>
        <span className="onboarding-step">第一版计划已建立</span>
        <h1>先从今天最重要的事开始</h1>
        <p>Agent 已根据孕18周、杭州和家庭成员生成今天与未来四周的行动。</p>
        <div className="ready-summary grouped-list">
          <div><strong>1</strong><span>今天优先事项</span></div>
          <div><strong>6</strong><span>未来四周任务</span></div>
          <div><strong>2</strong><span>家庭参与成员</span></div>
        </div>
      </main>
    </MobileScroll>
  );
}

function OnboardingFooter({ label, onNext }: { label: string; onNext: () => void }) {
  return <div className="onboarding-footer"><button onClick={onNext}>{label}<ChevronRightIcon /></button></div>;
}

export default function Prototype() {
  return (
    <AppStateProvider>
      <FlowStack initial={screenForTab("today")} />
      <GlobalAgentSheet />
      <AppToast />
    </AppStateProvider>
  );
}

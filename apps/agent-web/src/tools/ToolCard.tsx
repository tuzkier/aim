import type { ReactNode } from "react";
import { useApprovalBatch, useRegisterApproval } from "../approvals";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

/** 工具卡的外框。所有按 toolName 注册的渲染器共用它，保证流里视觉一致。 */
export const ToolCard = ({ children }: { children: ReactNode }) => (
  <div className="tool-card">{children}</div>
);

/**
 * 登记这一项在等待拍板，并显示它自己的选择。
 *
 * 按钮不在这里——整组共用一对，见 `ToolGroup`。用户说的是一件事，
 * 就该是一次拍板；拆成每项一次既不符合表达，也会让批次回不齐。
 */
export const ApprovalSlot = <TArgs,>({ props }: { props: ToolRenderProps<TArgs> }) => {
  const awaiting = isAwaitingApproval(props.approval);
  const approvalId = props.approval?.id;
  const { decisionOf, dispatching } = useApprovalBatch();

  useRegisterApproval(approvalId, awaiting);

  if (!awaiting || !approvalId) return null;
  const decision = decisionOf(approvalId);
  if (!decision) return null;

  return (
    <p className="tool-card__status">
      {dispatching ? "正在提交…" : decision.approved ? "待提交：收录" : "待提交：不收录"}
    </p>
  );
};

/**
 * 拍板之后这张卡的去向。
 *
 * 被否决、被取消、执行失败都要说出来。此前这些状态在界面上没有任何痕迹，
 * 用户只能看到卡片消失，分不清「存好了」和「出错了」。
 */
export const ToolStatusLine = <TArgs,>({ props }: { props: ToolRenderProps<TArgs> }) => {
  const approval = props.approval;
  if (isAwaitingApproval(approval)) return null;

  if (approval?.resolution === "cancelled") {
    return <p className="tool-card__status">已取消</p>;
  }
  if (approval?.resolution === "expired") {
    return <p className="tool-card__status">已超时，未执行</p>;
  }
  if (approval?.approved === false) {
    return <p className="tool-card__status">没有收录</p>;
  }
  if (props.isError) {
    return <p className="tool-card__status tool-card__status--error">执行失败</p>;
  }
  if (props.status?.type === "running") {
    return <p className="tool-card__status">正在执行…</p>;
  }
  if (props.result !== undefined) {
    const summary = (props.result as { summary?: string } | undefined)?.summary;
    return <p className="tool-card__status tool-card__status--done">{summary ?? "已完成"}</p>;
  }
  return null;
};

import type { ToolCallMessagePartProps } from "@assistant-ui/react";

/** 工具渲染器拿到的 props。参数类型由各渲染器自己收窄。 */
export type ToolRenderProps<TArgs> = ToolCallMessagePartProps<TArgs>;

/**
 * 这次调用还等着用户拍板。
 *
 * 三个条件缺一不可：有审批对象、还没有决定、也没有被主机判定为取消或过期。
 * 只看 `status.type === "requires-action"` 是不够的——那个状态在等待前端工具
 * 执行结果时也会出现，跟审批无关。
 */
export const isAwaitingApproval = (
  approval: ToolCallMessagePartProps["approval"],
): boolean => approval !== undefined && approval.approved === undefined && !approval.resolution;

/** 这条消息里还等着拍板的工具名。按消息算，确认按钮才不会挂到每条回复下面。 */
export const pendingApprovalTools = (parts: readonly unknown[]): string[] =>
  parts.flatMap((raw) => {
    const part = raw as {
      type?: string;
      toolName?: string;
      approval?: ToolCallMessagePartProps["approval"];
    };
    return part.type === "tool-call" && part.toolName && isAwaitingApproval(part.approval)
      ? [part.toolName]
      : [];
  });

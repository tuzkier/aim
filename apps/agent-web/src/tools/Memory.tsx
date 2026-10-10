import { useState } from "react";
import { makeAssistantToolUI } from "@assistant-ui/react";
import { loadNativeContext, notifyTurnFinished } from "../bridge";
import { useBizData } from "../bizData";
import { OpenNative } from "./OpenNative";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";
import { memoryHeadline, memoryOperationID } from "./memoryState";

function RememberCard(props: ToolRenderProps<{ text?: string }>) {
  const [undone, setUndone] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const { reload } = useBizData();
  const operation = memoryOperationID(props.result);
  const result = props.result as { data?: { record_id?: string; text?: string } } | undefined;

  const undo = async () => {
    if (!operation || busy) return;
    setBusy(true);
    setError(undefined);
    try {
      const context = await loadNativeContext();
      const response = await fetch(`${context.eveOrigin ?? ""}/api/v1/agent/operations/${encodeURIComponent(operation)}/undo`, {
        method: "POST", headers: { authorization: `Bearer ${context.token}` },
      });
      if (!response.ok) throw new Error("没能撤销，请重试");
      setUndone(true);
      reload();
      notifyTurnFinished(["record"]);
    } catch {
      setError("没能撤销，请重试");
    } finally { setBusy(false); }
  };

  return <ToolCard>
    <p className="tool-card__eyebrow">AIM 记得的事</p>
    <h3 className="tool-card__title">{undone ? "已撤销记忆" : memoryHeadline(props.result, props.isError)}</h3>
    <p className="tool-card__text">{result?.data?.text ?? props.args?.text}</p>
    {!undone && <ToolStatusLine props={props} />}
    {!undone && operation && <>
      <button type="button" className="btn btn--link" disabled={busy} onClick={undo}>{busy ? "正在撤销…" : "撤销记忆"}</button>
      <OpenNative kind="record" id={result?.data?.record_id} />
    </>}
    {error && <p className="tool-card__status tool-card__status--error">{error}</p>}
  </ToolCard>;
}

export const RememberUI = makeAssistantToolUI({ toolName: "remember", render: RememberCard });

export const ForgetMemoryUI = makeAssistantToolUI({
  toolName: "forget_memory",
  render: (props: ToolRenderProps<{ text?: string }>) => <ToolCard>
    <p className="tool-card__eyebrow">AIM 记得的事</p>
    <h3 className="tool-card__title">{isAwaitingApproval(props.approval) ? "要遗忘这条记忆吗？" : "遗忘记忆"}</h3>
    <p className="tool-card__text">{props.args?.text ?? "这条记忆"}</p>
    <p className="tool-card__disclaimer">确认后删除，不能撤销。以后可以重新记下。</p>
    <ApprovalSlot props={props} />
    <ToolStatusLine props={props} />
  </ToolCard>,
});

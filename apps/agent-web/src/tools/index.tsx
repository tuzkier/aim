import { AskQuestionUI } from "./AskQuestion";
import { AssignTaskUI } from "./AssignTask";
import { CompleteTaskUI } from "./CompleteTask";
import { CreateKnowledgeUI } from "./CreateKnowledge";
import { CreateRecordUI } from "./CreateRecord";
import { CreateTaskUI } from "./CreateTask";
import { DeleteTaskUI } from "./DeleteTask";
import { RecordFactUI } from "./RecordFact";
import { RescheduleTaskUI } from "./RescheduleTask";

/**
 * 按 toolName 注册的渲染器。
 *
 * 挂在 `AssistantRuntimeProvider` 里面即可生效；没有注册的工具由
 * `GenericToolView` 兜底（在 `Thread` 的 `ToolFallback` 上挂）。
 *
 * 加新工具时在这里补一个组件，而不是在流的渲染逻辑里加分支——渲染逻辑不该知道
 * 有哪些工具存在。
 */
export const ToolRenderers = () => (
  <>
    <CreateKnowledgeUI />
    <CreateTaskUI />
    <CreateRecordUI />
    <CompleteTaskUI />
    <RescheduleTaskUI />
    <DeleteTaskUI />
    <AssignTaskUI />
    <RecordFactUI />
    <AskQuestionUI />
  </>
);

export { GenericToolView } from "./GenericTool";

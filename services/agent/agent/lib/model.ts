import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { mockModel } from "eve/evals";
import { resolveAgentModelConfig } from "./model-config";

export const gateModel = mockModel({
  modelId: "glm-5.2",
  provider: "zai",
  respond: ({ lastUserMessage, toolResults }) => {
    if (lastUserMessage?.includes("context")) {
      if (toolResults.length > 0) {
        return `Runtime gate result: ${JSON.stringify(toolResults.at(-1)?.output)}`;
      }
      return { toolCalls: [{ name: "echo_context", input: {} }] };
    }

    if (lastUserMessage?.includes("expert")) {
      if (toolResults.length > 0) {
        return `Runtime gate result: ${JSON.stringify(toolResults.at(-1)?.output)}`;
      }
      return {
        toolCalls: [
          {
            name: "pregnancy-expert",
            input: { message: "Return the read-only pregnancy snapshot." },
          },
        ],
      };
    }

    if (lastUserMessage?.includes("plan")) {
      const latest = toolResults.at(-1)?.output as
        | {
            operationId?: string;
            data?: { task_id?: string; tasks?: Array<{ task_id?: string; version?: number }> };
          }
        | undefined;

      if (toolResults.length === 0) {
        return { toolCalls: [{ name: "list_tasks", input: {} }] };
      }

      if (latest?.operationId && latest.data?.task_id) {
        return `Plan change result: ${JSON.stringify(latest)}`;
      }

      // 读到待办后直接发起改期：确认卡本身就是预览，不再先走一次空壳预览。
      const firstTask = latest?.data?.tasks?.[0];
      if (firstTask?.task_id) {
        return {
          toolCalls: [
            {
              name: "reschedule_task",
              input: {
                taskId: firstTask.task_id,
                expectedVersion: firstTask.version ?? 1,
                kind: "delay",
                at: "2026-08-21T09:00:00.000Z",
              },
            },
          ],
        };
      }

      return {
        text: `Plan change result: ${JSON.stringify(latest)}`,
      };
    }

    if (toolResults.length > 0) {
      return `Runtime gate result: ${JSON.stringify(toolResults.at(-1)?.output)}`;
    }

    return "Aim agent runtime is ready.";
  },
});

export function createConfiguredModel() {
  const config = resolveAgentModelConfig();
  if (config.kind === "mock") {
    return gateModel;
  }

  return createOpenAICompatible({
    name: "deepseek",
    apiKey: config.apiKey,
    baseURL: config.baseURL,
  }).chatModel(config.model);
}

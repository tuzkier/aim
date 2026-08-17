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
            taskId?: string;
            status?: string;
          }
        | undefined;
      const taskSnapshot = toolResults
        .map((result) => result.output as { data?: { tasks?: Array<{ task_id?: string; version?: number }> } })
        .find((output) => (output.data?.tasks?.length ?? 0) > 0)?.data?.tasks?.[0];
      const firstTask = latest?.data?.tasks?.[0] ?? taskSnapshot;

      if (toolResults.length === 0) {
        return { toolCalls: [{ name: "list_tasks", input: {} }] };
      }

      if (latest?.status === "preview" && latest.taskId) {
        return {
          toolCalls: [
            {
              name: "update_task",
              input: {
                taskId: latest.taskId,
                action: "delay",
                expectedVersion: taskSnapshot?.version ?? 1,
                dueAt: "2026-08-21T09:00:00.000Z",
              },
            },
          ],
        };
      }

      if (latest?.operationId && latest.data?.task_id) {
        return `Plan change result: ${JSON.stringify(latest)}`;
      }

      if (firstTask?.task_id) {
        return {
          toolCalls: [
            {
              name: "preview_task_change",
              input: { taskId: firstTask.task_id, action: "snooze" },
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

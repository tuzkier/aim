import { mockModel } from "eve/evals";

export const gateModel = mockModel({
  modelId: "glm-5.2",
  provider: "zai",
  respond: ({ lastUserMessage, toolResults }) => {
    if (toolResults.length > 0) {
      return `Runtime gate result: ${JSON.stringify(toolResults.at(-1)?.output)}`;
    }

    if (lastUserMessage?.includes("context")) {
      return { toolCalls: [{ name: "echo_context", input: {} }] };
    }

    if (lastUserMessage?.includes("expert")) {
      return {
        toolCalls: [
          {
            name: "pregnancy-expert",
            input: { message: "Return the read-only pregnancy snapshot." },
          },
        ],
      };
    }

    return "Aim agent runtime is ready.";
  },
});

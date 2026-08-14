import type { ToolContext } from "eve/tools";
import { requireAimScope, requireSessionId } from "../auth/session-context.ts";

export type AimToolStatus = "completed" | "approval_required";

export type AimToolResult<TData extends Record<string, unknown> = Record<string, unknown>> = {
  operationId: string;
  status: AimToolStatus;
  summary: string;
  data: TData;
};

export class BusinessApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryable: boolean;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "BusinessApiError";
    this.status = status;
    this.code = code;
    this.retryable = status >= 500 || status === 408 || status === 429;
  }
}

type ToolContextLike = Pick<ToolContext, "session" | "callId"> &
  Partial<Pick<ToolContext, "abortSignal">>;

function apiBaseUrl(): string {
  return (process.env.AIM_API_INTERNAL_URL ?? "http://127.0.0.1:8000").replace(/\/$/, "");
}

function serviceSecret(): string {
  const secret = process.env.AGENT_SERVICE_SECRET?.trim();
  if (!secret) throw new Error("AGENT_SERVICE_SECRET is not configured");
  return secret;
}

function normalizeResult<TData extends Record<string, unknown>>(
  value: unknown,
): AimToolResult<TData> {
  if (!value || typeof value !== "object") throw new Error("business API returned an invalid result");
  const body = value as Record<string, unknown>;
  const operationId = body.operation_id ?? body.operationId;
  if (
    typeof operationId !== "string" ||
    (body.status !== "completed" && body.status !== "approval_required") ||
    typeof body.summary !== "string" ||
    !body.data ||
    typeof body.data !== "object" ||
    Array.isArray(body.data)
  ) {
    throw new Error("business API returned an invalid tool result");
  }
  return {
    operationId,
    status: body.status,
    summary: body.summary,
    data: body.data as TData,
  };
}

export async function callBusinessApi<TData extends Record<string, unknown>>(
  ctx: ToolContextLike,
  path: string,
  payload: Record<string, unknown> = {},
): Promise<AimToolResult<TData>> {
  const scope = requireAimScope(ctx);
  const sessionId = requireSessionId(ctx);
  const callId = ctx.callId.trim();
  if (!callId) throw new Error("Eve tool call has no idempotency call id");

  const response = await fetch(`${apiBaseUrl()}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "service-authorization": `Bearer ${serviceSecret()}`,
      "actor-account-id": scope.accountId,
      "family-id": scope.familyId,
      "pregnancy-id": scope.pregnancyId,
      "eve-session-id": sessionId,
      "idempotency-key": callId,
    },
    body: JSON.stringify(payload),
    signal: ctx.abortSignal,
  });

  let body: unknown;
  try {
    body = await response.json();
  } catch {
    body = undefined;
  }

  if (!response.ok) {
    const errorBody = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
    const details = errorBody.error && typeof errorBody.error === "object"
      ? (errorBody.error as Record<string, unknown>)
      : {};
    const code = typeof details.code === "string" ? details.code : `http_${response.status}`;
    const message = typeof details.message === "string" ? details.message : "business API request failed";
    throw new BusinessApiError(response.status, code, message);
  }

  return normalizeResult<TData>(body);
}

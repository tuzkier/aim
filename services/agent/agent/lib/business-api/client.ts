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

// The agent runtime's session-scoped auth context is intermittently unset on
// the first read immediately after a tool call starts, even though the
// session itself authenticated successfully (observed: the same tool call
// succeeds on a later attempt within the same session). The business API
// rejects that as a 400 "invalid agent scope" before recording any
// idempotency invocation, so retrying with the same call id is safe and
// cannot replay a stale result.
const SCOPE_RETRY_DELAY_MS = 150;

function extractErrorDetail(body: unknown, status: number): { code: string; message: string } {
  const errorBody = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
  const nested = errorBody.error && typeof errorBody.error === "object"
    ? (errorBody.error as Record<string, unknown>)
    : {};
  if (typeof nested.message === "string") {
    return {
      code: typeof nested.code === "string" ? nested.code : `http_${status}`,
      message: nested.message,
    };
  }
  if (typeof errorBody.detail === "string") {
    return { code: `http_${status}`, message: errorBody.detail };
  }
  return { code: `http_${status}`, message: "business API request failed" };
}

async function requestOnce<TData extends Record<string, unknown>>(
  ctx: ToolContextLike,
  path: string,
  payload: Record<string, unknown>,
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
    const { code, message } = extractErrorDetail(body, response.status);
    throw new BusinessApiError(response.status, code, message);
  }

  return normalizeResult<TData>(body);
}

function isTransientScopeError(error: unknown): error is BusinessApiError {
  return (
    error instanceof BusinessApiError &&
    error.status === 400 &&
    error.message === "invalid agent scope"
  );
}

export async function callBusinessApi<TData extends Record<string, unknown>>(
  ctx: ToolContextLike,
  path: string,
  payload: Record<string, unknown> = {},
): Promise<AimToolResult<TData>> {
  try {
    return await requestOnce<TData>(ctx, path, payload);
  } catch (error) {
    if (!isTransientScopeError(error)) throw error;
    await new Promise((resolve) => setTimeout(resolve, SCOPE_RETRY_DELAY_MS));
    return requestOnce<TData>(ctx, path, payload);
  }
}

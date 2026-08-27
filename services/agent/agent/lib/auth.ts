import type { AuthFn } from "eve/channels/auth";

const requiredHeaders = [
  "x-aim-account-id",
  "x-aim-family-id",
  "x-aim-pregnancy-id",
] as const;

type ResolvedScope = {
  accountId: string;
  familyId: string;
  pregnancyId: string;
};

function apiBaseUrl(): string {
  return (process.env.AIM_API_INTERNAL_URL ?? "http://127.0.0.1:8000").replace(/\/$/, "");
}

/**
 * 把会话票送到业务 API 换取可信 scope。
 *
 * 验签必须发生在持有 `AUTH_SECRET` 的那一侧，而且家庭与孕期要由服务端按账号查出——
 * 这两件事合起来才能保证调用方无法自选身份。
 */
async function resolveScope(token: string): Promise<ResolvedScope | null> {
  const secret = process.env.AGENT_SERVICE_SECRET?.trim();
  if (!secret) return null;

  try {
    const response = await fetch(`${apiBaseUrl()}/internal/agent-tools/resolve-session`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "service-authorization": `Bearer ${secret}`,
      },
      body: JSON.stringify({ token }),
    });
    if (!response.ok) return null;

    const body = (await response.json()) as Record<string, unknown>;
    const accountId = body.account_id;
    const familyId = body.family_id;
    const pregnancyId = body.pregnancy_id;
    if (typeof accountId !== "string" || typeof familyId !== "string") return null;

    return {
      accountId,
      familyId,
      // 还没建孕期档案的账号也该能进来问问题，此时孕期 scope 为空串，
      // 工具那边会自己拦（requireAimScope）。
      pregnancyId: typeof pregnancyId === "string" ? pregnancyId : "",
    };
  } catch {
    // 业务 API 不可达时关门，而不是退回自报身份——降级不能降到无鉴权。
    return null;
  }
}

/**
 * Eve 通道的鉴权。
 *
 * 身份只能从签名过的会话票推导：票送到业务 API 换取 scope，
 * **客户端送来的 `x-aim-*` 头一概不看**。这个通道经 nginx 直接对公网暴露，
 * 一旦采信调用方自报的 scope，就等于任何人都能指定自己是谁。
 *
 * 唯一的例外是显式配置 `EVE_EVAL_AUTH_TOKEN` 时的 eval 旁路，见下。
 */
export const aimSessionAuth: AuthFn<Request> = async (request) => {
  const authorization = request.headers.get("authorization")?.trim();

  // eval 专用旁路：只在显式配了 EVE_EVAL_AUTH_TOKEN 时存在，且要求完全相等。
  const evalToken = process.env.EVE_EVAL_AUTH_TOKEN?.trim();
  if (evalToken && authorization === `Bearer ${evalToken}`) {
    const scoped = Object.fromEntries(
      requiredHeaders.map((header) => [header, request.headers.get(header)?.trim() ?? ""]),
    );
    if (requiredHeaders.every((header) => scoped[header]!.length > 0)) {
      const accountId = scoped["x-aim-account-id"]!;
      return {
        attributes: {
          accountId,
          familyId: scoped["x-aim-family-id"]!,
          pregnancyId: scoped["x-aim-pregnancy-id"]!,
        },
        authenticator: "eve-eval-token-with-scope",
        issuer: "aim-api",
        principalId: accountId,
        principalType: "user",
      };
    }
    return {
      attributes: {
        accountId: "eval_account",
        familyId: "eval_family",
        pregnancyId: "eval_pregnancy",
      },
      authenticator: "eve-eval-token",
      issuer: "aim-api",
      principalId: "eval_account",
      principalType: "user",
    };
  }

  if (!authorization?.startsWith("Bearer ")) return null;
  const token = authorization.slice("Bearer ".length).trim();
  if (!token) return null;

  const scope = await resolveScope(token);
  if (!scope) return null;

  return {
    attributes: {
      accountId: scope.accountId,
      familyId: scope.familyId,
      pregnancyId: scope.pregnancyId,
    },
    authenticator: "aim-session-token",
    issuer: "aim-api",
    principalId: scope.accountId,
    principalType: "user",
  };
};

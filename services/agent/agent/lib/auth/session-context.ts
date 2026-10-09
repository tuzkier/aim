import type { SessionContext } from "eve/tools";

export type AimScope = {
  accountId: string;
  familyId: string;
  pregnancyId: string;
};

type AuthenticatedSessionContext = Pick<SessionContext, "session">;

function requiredAttribute(
  attributes: Readonly<Record<string, string | readonly string[]>> | undefined,
  key: string,
): string {
  const value = attributes?.[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`authenticated Aim session is missing ${key}`);
  }
  return value.trim();
}

/**
 * Resolve business scope from Eve's verified channel context.
 *
 * Tool inputs are intentionally not accepted here. The model must never be
 * able to choose the account, family, or pregnancy used for a business call.
 */
export function requireAimScope(ctx: AuthenticatedSessionContext): AimScope {
  const attributes = ctx.session.auth.current?.attributes;
  const pregnancyId = attributes?.pregnancyId;
  // 鉴权时没有孕期档案的账号 pregnancyId 为空串（见 lib/auth.ts）。这句话会回到
  // 模型手里并被转述给用户，所以写成用户能照着做的中文。
  if (typeof pregnancyId !== "string" || pregnancyId.trim().length === 0) {
    throw new Error("还没有建立孕期档案，请先在 App 里填写预产期或末次月经");
  }
  return {
    accountId: requiredAttribute(attributes, "accountId"),
    familyId: requiredAttribute(attributes, "familyId"),
    pregnancyId: pregnancyId.trim(),
  };
}

export function requireSessionId(ctx: AuthenticatedSessionContext): string {
  const sessionId = ctx.session.id.trim();
  if (sessionId.length === 0) throw new Error("authenticated Eve session has no id");
  return sessionId;
}

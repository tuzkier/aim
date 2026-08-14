import type { AuthFn } from "eve/channels/auth";

const requiredHeaders = [
  "x-aim-account-id",
  "x-aim-family-id",
  "x-aim-pregnancy-id",
] as const;

export const aimSessionAuth: AuthFn<Request> = async (request) => {
  const evalToken = process.env.EVE_EVAL_AUTH_TOKEN?.trim();
  const authorization = request.headers.get("authorization")?.trim();
  if (evalToken && authorization === `Bearer ${evalToken}`) {
    const scopedHeaders = Object.fromEntries(
      requiredHeaders.map((header) => [header, request.headers.get(header)?.trim() ?? ""]),
    );
    if (requiredHeaders.every((header) => scopedHeaders[header].length > 0)) {
      const accountId = scopedHeaders["x-aim-account-id"];
      const familyId = scopedHeaders["x-aim-family-id"];
      const pregnancyId = scopedHeaders["x-aim-pregnancy-id"];
      return {
        attributes: { accountId, familyId, pregnancyId },
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

  const values = Object.fromEntries(
    requiredHeaders.map((header) => [header, request.headers.get(header)?.trim() ?? ""]),
  );

  if (requiredHeaders.some((header) => values[header].length === 0)) {
    return null;
  }

  const accountId = values["x-aim-account-id"];
  const familyId = values["x-aim-family-id"];
  const pregnancyId = values["x-aim-pregnancy-id"];

  return {
    attributes: { accountId, familyId, pregnancyId },
    authenticator: "aim-dev-header",
    issuer: "aim-api",
    principalId: accountId,
    principalType: "user",
  };
};

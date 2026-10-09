import { eveChannel } from "eve/channels/eve";
import { withAuthChallenges } from "eve/channels/auth";
import { aimSessionAuth } from "../lib/auth";

export default eveChannel({
  // Local development still requires the same explicit account/family/pregnancy
  // scope headers as production. This prevents localDev() from masking auth
  // regressions in the app-to-runtime contract.
  auth: [withAuthChallenges(aimSessionAuth, [{ scheme: "Bearer" }])],
  // 只收图片，单张不超过 2 MB（网页端已压到几百 KB）。超了由 Eve 直接拒收。
  uploadPolicy: { allowedMediaTypes: ["image/*"], maxBytes: 2 * 1024 * 1024 },
});

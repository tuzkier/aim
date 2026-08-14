import { eveChannel } from "eve/channels/eve";
import { withAuthChallenges } from "eve/channels/auth";
import { aimSessionAuth } from "../lib/auth";

export default eveChannel({
  // Local development still requires the same explicit account/family/pregnancy
  // scope headers as production. This prevents localDev() from masking auth
  // regressions in the app-to-runtime contract.
  auth: [withAuthChallenges(aimSessionAuth, [{ scheme: "Bearer" }])],
});

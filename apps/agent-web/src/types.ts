/** 与 eve 客户端一致的会话游标形状。 */
export interface ClientSessionState {
  readonly sessionId: string;
  readonly streamIndex: number;
}

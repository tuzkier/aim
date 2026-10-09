import type { WriteKind } from "./turnWrites";

/**
 * 把一阵写入合并成一次刷新。
 *
 * 一轮里批量建 38 条待办时，逐条通知会让原生和网页各刷 38 遍——线上实测 3 秒内
 * 133 个请求、52 个被网关限流。这里等写入停下来 delayMs 再报一次；一直有写入
 * 进来也不会无限推迟，最多等 maxWaitMs。
 */
export const createWriteBatcher = (options: {
  delayMs: number;
  maxWaitMs: number;
  flush: (kinds: WriteKind[]) => void;
}) => {
  const pending = new Set<WriteKind>();
  let quietTimer: ReturnType<typeof setTimeout> | undefined;
  let maxTimer: ReturnType<typeof setTimeout> | undefined;

  const clear = () => {
    if (quietTimer) clearTimeout(quietTimer);
    if (maxTimer) clearTimeout(maxTimer);
    quietTimer = maxTimer = undefined;
  };

  const fire = () => {
    clear();
    if (pending.size === 0) return;
    const kinds = [...pending];
    pending.clear();
    options.flush(kinds);
  };

  return {
    add(kinds: readonly WriteKind[]) {
      if (kinds.length === 0) return;
      for (const kind of kinds) pending.add(kind);
      if (quietTimer) clearTimeout(quietTimer);
      quietTimer = setTimeout(fire, options.delayMs);
      maxTimer ??= setTimeout(fire, options.maxWaitMs);
    },
    dispose() {
      clear();
      pending.clear();
    },
  };
};

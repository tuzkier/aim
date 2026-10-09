import { hasNativeShell, openNative } from "../bridge";

/** 已执行的卡片上跳回原生详情页。浏览器开发时没有原生外壳，不显示。 */
export const OpenNative = ({
  kind,
  id,
}: {
  kind: "task" | "record" | "knowledge";
  id?: string;
}) =>
  id && hasNativeShell() ? (
    <button type="button" className="btn btn--link" onClick={() => openNative({ kind, id })}>
      查看
    </button>
  ) : null;

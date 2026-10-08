import type { AttachmentAdapter, CompleteAttachment, PendingAttachment } from "@assistant-ui/react";

export const MAX_IMAGES = 4;
const MAX_EDGE = 1600;
const QUALITY = 0.8;

export const fitWithin = (width: number, height: number, maxEdge: number) => {
  const scale = Math.min(1, maxEdge / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
};

/** 上传成功的一张图：第几条用户消息里的、选图时的先后次序。 */
export type UploadedImage = { id: string; message: number; order: number };
export type SentImage = { id: string; message: number; index: number };

/**
 * 同一条消息里的几张图是并行上传的，完成先后不固定；按选图次序编号，
 * 「第 2 张」才和用户看到的第 2 张是同一张。
 */
export const numberImages = (images: readonly UploadedImage[]): SentImage[] => {
  const sorted = [...images].sort((a, b) => a.message - b.message || a.order - b.order);
  const seen = new Map<number, number>();
  return sorted.map(({ id, message }) => {
    const index = (seen.get(message) ?? 0) + 1;
    seen.set(message, index);
    return { id, message, index };
  });
};

/** 本段对话里发过的所有图片编号。每轮都带给模型，它挂图时才有编号可用。 */
export const imagesContext = (images: readonly SentImage[]): string | null =>
  images.length
    ? "Photos the user sent in this conversation (use these ids in attachmentIds):\n" +
      images.map((image) => `- message ${image.message}, photo ${image.index}: ${image.id}`).join("\n")
    : null;

/** 压成最长边 1600 的 JPEG。iPhone 的 HEIC 由 WebView 解码后同样走这里。 */
const compress = async (file: File): Promise<Blob> => {
  const bitmap = await createImageBitmap(file);
  const { width, height } = fitWithin(bitmap.width, bitmap.height, MAX_EDGE);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();
  return new Promise((resolve, reject) =>
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("图片处理失败"))),
      "image/jpeg",
      QUALITY,
    ),
  );
};

const toDataUrl = (blob: Blob): Promise<string> =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });

/**
 * 选图时压缩，发送时上传到业务服务并转成消息内容。
 *
 * 上传失败时 send 抛错，assistant-ui 会把整条消息退回输入框、图片保留——
 * 不能出现「模型看到了图、记录却挂不上」。抛出的错误没人展示，
 * 所以文案经 onError 交给页面显示；再点发送即重试。
 */
export const createImageAttachmentAdapter = (options: {
  upload: (blob: Blob) => Promise<string>;
  onUploaded: (image: { id: string; order: number }) => void;
  onError: (message: string | null) => void;
}): AttachmentAdapter => {
  // 输入框里还没发出去的图。多选时各张是同时加入的，输入框自己的列表要等压缩完才更新，
  // 拿它判断上限会漏，所以在这里同步占位。
  const waiting = new Set<string>();
  let order = 0;
  const orderOf = new Map<string, number>();

  return {
    accept: "image/*",
    async add({ file }): Promise<PendingAttachment> {
      if (waiting.size >= MAX_IMAGES) {
        const message = `一次最多发 ${MAX_IMAGES} 张图片，多出的没有加上`;
        options.onError(message);
        throw new Error(message);
      }
      const id = crypto.randomUUID();
      waiting.add(id);
      orderOf.set(id, ++order);
      options.onError(null);
      try {
        const compressed = await compress(file);
        const name = `${file.name.replace(/\.[^.]+$/, "") || "photo"}.jpg`;
        return {
          id,
          type: "image",
          name,
          contentType: "image/jpeg",
          file: new File([compressed], name, { type: "image/jpeg" }),
          status: { type: "requires-action", reason: "composer-send" },
        };
      } catch (cause) {
        waiting.delete(id);
        options.onError("这张图片打不开，换一张试试");
        throw cause;
      }
    },
    async remove(attachment) {
      waiting.delete(attachment.id);
    },
    async send(attachment): Promise<CompleteAttachment> {
      let id: string;
      try {
        id = await options.upload(attachment.file);
      } catch (cause) {
        options.onError("图片上传失败，请检查网络后再点发送");
        throw cause;
      }
      options.onError(null);
      waiting.delete(attachment.id);
      options.onUploaded({ id, order: orderOf.get(attachment.id) ?? order });
      return {
        ...attachment,
        status: { type: "complete" },
        content: [
          {
            type: "file",
            data: await toDataUrl(attachment.file),
            mimeType: "image/jpeg",
            filename: attachment.name,
          },
        ],
      };
    },
  };
};

/** 原生（首页「拍报告」）传来的图片内容转成文件，交给输入框的附件适配器。 */
export const dataUrlToFile = (dataUrl: string, name: string): File => {
  const [header, payload = ""] = dataUrl.split(",", 2);
  const type = /data:([^;]+)/.exec(header)?.[1] ?? "image/jpeg";
  const binary = atob(payload);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new File([bytes], name, { type });
};

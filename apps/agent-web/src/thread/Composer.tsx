import { AttachmentPrimitive, ComposerPrimitive, type Attachment } from "@assistant-ui/react";
import { useEffect, useState, type ReactNode } from "react";

/** 附件里能直接显示的图片地址：待发的是本地文件，发出去的是图片内容本身。 */
export const imageSource = (attachment: Attachment): string | null => {
  for (const part of attachment.content ?? []) {
    if (part.type === "image") return part.image;
    if (part.type === "file" && part.mimeType.startsWith("image/")) return part.data;
  }
  return null;
};

const PendingImage = ({ attachment }: { attachment: Attachment }) => {
  const file = "file" in attachment ? attachment.file : undefined;
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (!file) return;
    const next = URL.createObjectURL(file);
    setUrl(next);
    return () => URL.revokeObjectURL(next);
  }, [file]);
  const src = url ?? imageSource(attachment);
  return (
    <AttachmentPrimitive.Root className="pending-image">
      {src ? <img src={src} alt="" /> : <span className="pending-image__loading" />}
      <AttachmentPrimitive.Remove className="pending-image__remove" aria-label="删掉这张图">
        ×
      </AttachmentPrimitive.Remove>
    </AttachmentPrimitive.Root>
  );
};

const PhotoIcon = () => (
  <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
    <rect x="3" y="5" width="18" height="14" rx="3" fill="none" stroke="currentColor" strokeWidth="1.8" />
    <circle cx="9" cy="10" r="1.8" fill="currentColor" />
    <path d="M4.5 17.5 10 13l3.5 3 2.5-2 3.5 3" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
  </svg>
);

/**
 * 输入框。上方一层放页面标签、上传提示和待发的图片；图片按钮走系统的文件选择，
 * iOS 上会给出拍照、照片图库等选项。
 */
export const Composer = ({ chip, error }: { chip?: ReactNode; error?: string | null }) => (
  <>
    {chip}
    {error ? (
      <p className="composer__error" role="alert">
        {error}
      </p>
    ) : null}
    <div className="composer__images">
      <ComposerPrimitive.Attachments>
        {({ attachment }) => <PendingImage attachment={attachment} />}
      </ComposerPrimitive.Attachments>
    </div>
    <ComposerPrimitive.Root className="composer">
      <ComposerPrimitive.AddAttachment className="composer__image-button" aria-label="发图片" multiple>
        <PhotoIcon />
      </ComposerPrimitive.AddAttachment>
      <ComposerPrimitive.Input
        className="composer__input"
        placeholder="告诉我你现在在担心什么"
        rows={1}
      />
      <ComposerPrimitive.Send className="composer__send">发送</ComposerPrimitive.Send>
    </ComposerPrimitive.Root>
  </>
);

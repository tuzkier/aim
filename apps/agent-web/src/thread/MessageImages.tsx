import { MessagePrimitive, type Attachment } from "@assistant-ui/react";
import { useState } from "react";
import { imageSource } from "./Composer";

const MessageImage = ({ attachment }: { attachment: Attachment }) => {
  const [open, setOpen] = useState(false);
  const src = imageSource(attachment);
  if (!src) return null;
  return (
    <>
      <button type="button" className="message-image" onClick={() => setOpen(true)}>
        <img src={src} alt="你发的图片" />
      </button>
      {open ? (
        <button
          type="button"
          className="image-viewer"
          onClick={() => setOpen(false)}
          aria-label="关闭大图"
        >
          <img src={src} alt="" />
        </button>
      ) : null}
    </>
  );
};

/** 用户消息里的图片。对话记录里存的就是图片内容，重开对话也能直接显示。点开看大图。 */
export const MessageImages = () => (
  <div className="msg__images">
    <MessagePrimitive.Attachments>
      {({ attachment }) => <MessageImage attachment={attachment} />}
    </MessagePrimitive.Attachments>
  </div>
);

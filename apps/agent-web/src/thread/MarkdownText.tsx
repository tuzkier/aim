import type { TextMessagePartComponent } from "@assistant-ui/react";
import type { ReactNode } from "react";

/**
 * 助手文字的渲染。
 *
 * 只认三样：段落、`-` / `1.` 列表、行内 `**加粗**`。这不是「先实现一部分」，
 * 而是刻意划的边界——指令里就是这么告诉模型的，客户端和指令必须对齐。
 * 此前指令说了「行内加粗可以」，渲染却从没实现，于是 `**待办内容**` 带着星号
 * 直接摆在用户面前。
 *
 * 没有引第三方 Markdown 库：需要渲染的子集就这么大，而现成的库会把标题、表格、
 * 代码块一并带进来——那些恰恰是我们不希望模型输出、也不打算渲染的东西。
 */

/** 把 `**加粗**` 切成片段。转义留给 React，这里只做结构。 */
const renderInline = (text: string): ReactNode[] =>
  text.split(/(\*\*[^*]+\*\*)/g).map((piece, index) => {
    if (piece.startsWith("**") && piece.endsWith("**") && piece.length > 4) {
      return <strong key={index}>{piece.slice(2, -2)}</strong>;
    }
    return piece;
  });

type Block =
  | { kind: "p"; lines: string[] }
  | { kind: "ul"; items: string[] }
  | { kind: "ol"; items: string[] };

const BULLET = /^\s*[-*•]\s+(.*)$/;
const NUMBERED = /^\s*\d+[.)]\s+(.*)$/;

/**
 * 按行归组。空行分段；列表项连续成一组。
 *
 * 模型的输出常带首尾空行和不规整的缩进，直接 `pre-wrap` 会把气泡撑得很高，
 * 所以这里丢掉空白行而不是保留它们。
 */
const toBlocks = (text: string): Block[] => {
  const blocks: Block[] = [];
  for (const raw of text.split("\n")) {
    const line = raw.trimEnd();
    const bullet = BULLET.exec(line);
    const numbered = NUMBERED.exec(line);
    const last = blocks.at(-1);

    if (bullet) {
      if (last?.kind === "ul") last.items.push(bullet[1]!);
      else blocks.push({ kind: "ul", items: [bullet[1]!] });
    } else if (numbered) {
      if (last?.kind === "ol") last.items.push(numbered[1]!);
      else blocks.push({ kind: "ol", items: [numbered[1]!] });
    } else if (line.trim() === "") {
      // 空行只作分段用，本身不产生元素。
      if (last?.kind === "p") blocks.push({ kind: "p", lines: [] });
    } else if (last?.kind === "p") {
      last.lines.push(line);
    } else {
      blocks.push({ kind: "p", lines: [line] });
    }
  }
  return blocks.filter((block) => (block.kind === "p" ? block.lines.length > 0 : true));
};

export const MarkdownText: TextMessagePartComponent = ({ text }) => (
  <>
    {toBlocks(text ?? "").map((block, index) => {
      if (block.kind === "ul") {
        return (
          <ul key={index}>
            {block.items.map((item, i) => (
              <li key={i}>{renderInline(item)}</li>
            ))}
          </ul>
        );
      }
      if (block.kind === "ol") {
        return (
          <ol key={index}>
            {block.items.map((item, i) => (
              <li key={i}>{renderInline(item)}</li>
            ))}
          </ol>
        );
      }
      return <p key={index}>{renderInline(block.lines.join("\n"))}</p>;
    })}
  </>
);

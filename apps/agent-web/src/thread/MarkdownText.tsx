import type { TextMessagePartComponent } from "@assistant-ui/react";
import { Fragment, type ReactNode } from "react";
import { openNative } from "../bridge";
import { parseInline, type CitationPiece } from "./citations";

/**
 * 助手文字的渲染。
 *
 * 只认三样：段落、`-` / `1.` 列表、行内 `**加粗**`；另外把资料引用标记
 * `[[ref:…|…]]` / `[[record:…|…]]` 渲染成可点的来源胶囊。这不是「先实现一部分」，
 * 而是刻意划的边界——指令里就是这么告诉模型的，客户端和指令必须对齐。
 * 此前指令说了「行内加粗可以」，渲染却从没实现，于是 `**待办内容**` 带着星号
 * 直接摆在用户面前。
 *
 * 没有引第三方 Markdown 库：需要渲染的子集就这么大，而现成的库会把标题、表格、
 * 代码块一并带进来——那些恰恰是我们不希望模型输出、也不打算渲染的东西。
 */

/**
 * 资料引用渲染成来源胶囊，点了让原生打开对应的百科条目或记录。
 * 浏览器里没有原生外壳时照样显示，点击只会在 `openNative` 里 warn 一下。
 */
const renderPiece = (piece: CitationPiece, key: number): ReactNode => {
  if (piece.kind === "text") return piece.text;
  return (
    <button
      key={key}
      type="button"
      className="aim-citation"
      onClick={() => openNative({ kind: piece.kind === "ref" ? "encyclopedia" : "record", id: piece.id })}
    >
      <span className="aim-citation__icon" aria-hidden="true">
        {piece.kind === "ref" ? "📖" : "🗂"}
      </span>
      {piece.title}
    </button>
  );
};

/** 切出引用和 `**加粗**`，规则见 `parseInline`。转义留给 React，这里只做结构。 */
const renderInline = (text: string): ReactNode[] =>
  parseInline(text).map((span, index) => {
    const children = span.pieces.map(renderPiece);
    return span.bold ? <strong key={index}>{children}</strong> : <Fragment key={index}>{children}</Fragment>;
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

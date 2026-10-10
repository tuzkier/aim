/**
 * AIM 回答里的引用标记：[[ref:<百科编号>|<标题>]]、[[record:<记录编号>|<标题>]]。
 *
 * 只有格式完全合法的才变成可点的来源胶囊；其余去掉方括号只留文字——
 * 模型偶尔会写坏标记，宁可少一个可点入口，也不能把一个跳不过去的编号做成按钮。
 */
export type CitationPiece =
  | { kind: "text"; text: string }
  | { kind: "ref"; id: string; title: string }
  | { kind: "record"; id: string; title: string };

const MARK = /\[\[(ref|record):([^\]|]+)(?:\|([^\]]+))?\]\]/g;
const REF_ID = /^[a-z]+\.[a-z0-9-]+$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const parseCitations = (text: string): CitationPiece[] => {
  const pieces: CitationPiece[] = [];
  let last = 0;
  for (const match of text.matchAll(MARK)) {
    const [whole, kind, rawId, rawTitle] = match;
    const index = match.index ?? 0;
    if (index > last) pieces.push({ kind: "text", text: text.slice(last, index) });
    const id = rawId!.trim();
    const title = rawTitle?.trim();
    const valid = kind === "ref" ? REF_ID.test(id) : UUID.test(id);
    if (valid && title) {
      pieces.push({ kind: kind as "ref" | "record", id, title });
    } else {
      pieces.push({ kind: "text", text: title || id });
    }
    last = index + whole.length;
  }
  if (last < text.length) pieces.push({ kind: "text", text: text.slice(last) });
  return pieces.length > 0 ? pieces : [{ kind: "text", text }];
};

/** 一段行内文字：要么普通、要么加粗，里面可以夹着引用。 */
export interface InlineSpan {
  bold: boolean;
  pieces: CitationPiece[];
}

/** 占位符用私用区字符，正文里不会自然出现。 */
const HOLE_OPEN = "\uE000";
const HOLE_CLOSE = "\uE001";
const HOLE = /\uE000(\d+)\uE001/g;
const STRAY_HOLE_CHARS = /[\uE000\uE001]/g;
const BOLD = /(\*\*[^*]+\*\*)/g;

/**
 * 行内解析：先切出引用，再在剩下的文字上按原规则切 `**加粗**`。
 *
 * 引用先换成占位符再切加粗，是为了让 `**重点[[ref:…|…]]**` 这种加粗包住引用的
 * 写法仍然成对匹配——若直接对引用两侧的文字片段各自切加粗，两个 `**` 会被
 * 引用隔开、各自落单，原样露在界面上。占位符里没有 `*`，不影响加粗的匹配规则。
 */
export const parseInline = (text: string): InlineSpan[] => {
  const citations: CitationPiece[] = [];
  const flat = parseCitations(text)
    .map((piece) => {
      if (piece.kind === "text") return piece.text.replace(STRAY_HOLE_CHARS, "");
      citations.push(piece);
      return `${HOLE_OPEN}${citations.length - 1}${HOLE_CLOSE}`;
    })
    .join("");

  const expand = (segment: string): CitationPiece[] => {
    const pieces: CitationPiece[] = [];
    let last = 0;
    for (const match of segment.matchAll(HOLE)) {
      const index = match.index ?? 0;
      if (index > last) pieces.push({ kind: "text", text: segment.slice(last, index) });
      pieces.push(citations[Number(match[1])]!);
      last = index + match[0].length;
    }
    if (last < segment.length) pieces.push({ kind: "text", text: segment.slice(last) });
    return pieces;
  };

  return flat
    .split(BOLD)
    .filter((segment) => segment !== "")
    .map((segment) =>
      segment.startsWith("**") && segment.endsWith("**") && segment.length > 4
        ? { bold: true, pieces: expand(segment.slice(2, -2)) }
        : { bold: false, pieces: expand(segment) },
    );
};

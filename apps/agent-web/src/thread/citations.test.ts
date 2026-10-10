import { describe, expect, it } from "vitest";
import { parseCitations, parseInline } from "./citations";

describe("parseCitations", () => {
  it("切出百科与记录引用", () => {
    expect(parseCitations("糖耐量前要空腹[[ref:checkup.ogtt|糖耐量]]。上次结果[[record:0b6c1a2e-1111-4a2b-9c3d-123456789abc|10月3日产检]]")).toEqual([
      { kind: "text", text: "糖耐量前要空腹" },
      { kind: "ref", id: "checkup.ogtt", title: "糖耐量" },
      { kind: "text", text: "。上次结果" },
      { kind: "record", id: "0b6c1a2e-1111-4a2b-9c3d-123456789abc", title: "10月3日产检" },
    ]);
  });

  it("格式不合法时只留标题，不成为可点引用", () => {
    expect(parseCitations("见[[ref:不合法|某条]]")).toEqual([
      { kind: "text", text: "见" },
      { kind: "text", text: "某条" },
    ]);
    expect(parseCitations("见[[record:not-a-uuid|某次]]")).toEqual([
      { kind: "text", text: "见" },
      { kind: "text", text: "某次" },
    ]);
  });

  it("缺标题时用编号兜底的文字，不渲染胶囊", () => {
    expect(parseCitations("[[ref:checkup.ogtt]]")).toEqual([{ kind: "text", text: "checkup.ogtt" }]);
  });

  it("没有标记时原样返回", () => {
    expect(parseCitations("普通的一句话")).toEqual([{ kind: "text", text: "普通的一句话" }]);
  });
});

const RECORD_ID = "0b6c1a2e-1111-4a2b-9c3d-123456789abc";

/** 把结果里所有文字片段拼起来，用来断言标记符号没有漏到界面上。 */
const visibleText = (spans: ReturnType<typeof parseInline>): string =>
  spans
    .flatMap((span) => span.pieces)
    .map((piece) => (piece.kind === "text" ? piece.text : piece.title))
    .join("");

describe("parseInline", () => {
  it("没有引用时加粗规则与原来一致", () => {
    expect(parseInline("先**空腹**再去")).toEqual([
      { bold: false, pieces: [{ kind: "text", text: "先" }] },
      { bold: true, pieces: [{ kind: "text", text: "空腹" }] },
      { bold: false, pieces: [{ kind: "text", text: "再去" }] },
    ]);
  });

  it("不成对的星号原样保留", () => {
    expect(parseInline("a ** b")).toEqual([{ bold: false, pieces: [{ kind: "text", text: "a ** b" }] }]);
  });

  it("加粗包住引用时，引用仍是胶囊，星号和方括号都不露出来", () => {
    const spans = parseInline("**重点[[ref:checkup.ogtt|糖耐量]]**");
    expect(spans).toEqual([
      {
        bold: true,
        pieces: [
          { kind: "text", text: "重点" },
          { kind: "ref", id: "checkup.ogtt", title: "糖耐量" },
        ],
      },
    ]);
    expect(visibleText(spans)).not.toMatch(/\*\*|\[\[/);
  });

  it("加粗只包一个引用", () => {
    expect(parseInline(`见**[[record:${RECORD_ID}|10月3日产检]]**。`)).toEqual([
      { bold: false, pieces: [{ kind: "text", text: "见" }] },
      { bold: true, pieces: [{ kind: "record", id: RECORD_ID, title: "10月3日产检" }] },
      { bold: false, pieces: [{ kind: "text", text: "。" }] },
    ]);
  });

  it("加粗与引用并列", () => {
    expect(parseInline("先**空腹**，见[[ref:checkup.ogtt|糖耐量]]")).toEqual([
      { bold: false, pieces: [{ kind: "text", text: "先" }] },
      { bold: true, pieces: [{ kind: "text", text: "空腹" }] },
      {
        bold: false,
        pieces: [
          { kind: "text", text: "，见" },
          { kind: "ref", id: "checkup.ogtt", title: "糖耐量" },
        ],
      },
    ]);
  });

  it("不合法的引用在加粗里退化成普通加粗文字", () => {
    const spans = parseInline("**见[[ref:不合法|某条]]**");
    expect(spans).toEqual([{ bold: true, pieces: [{ kind: "text", text: "见某条" }] }]);
    expect(visibleText(spans)).not.toMatch(/\*\*|\[\[/);
  });
});

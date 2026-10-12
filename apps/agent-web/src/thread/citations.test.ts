import { describe, expect, it } from "vitest";
import { parseCitations, parseInline } from "./citations";

const RECORD_ID = "0b6c1a2e-1111-4a2b-9c3d-123456789abc";

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

  it("空标题用编号兜底，不漏出方括号", () => {
    expect(parseCitations("[[ref:a.b|]]")).toEqual([{ kind: "text", text: "a.b" }]);
  });

  it("标题里含竖线时整体保留", () => {
    expect(parseCitations("[[ref:checkup.ogtt|糖耐量|OGTT]]")).toEqual([
      { kind: "ref", id: "checkup.ogtt", title: "糖耐量|OGTT" },
    ]);
  });

  it("编号两侧带空白时 trim 后照常成胶囊", () => {
    expect(parseCitations("[[ref: checkup.ogtt |糖耐量]]")).toEqual([
      { kind: "ref", id: "checkup.ogtt", title: "糖耐量" },
    ]);
    expect(parseCitations(`[[record: ${RECORD_ID} |10月3日产检]]`)).toEqual([
      { kind: "record", id: RECORD_ID, title: "10月3日产检" },
    ]);
  });

  it("编号中间有空白时不合法，只显示标题、不露方括号", () => {
    expect(parseCitations("[[ref:bad id|标题]]")).toEqual([{ kind: "text", text: "标题" }]);
  });

  it("记录引用缺标题时显示「记录」，不露出编号", () => {
    expect(parseCitations(`[[record:${RECORD_ID}]]`)).toEqual([{ kind: "text", text: "记录" }]);
    expect(parseCitations(`[[record:${RECORD_ID}|]]`)).toEqual([{ kind: "text", text: "记录" }]);
  });

  it("没闭合的标记不吞掉后面的正文和合法引用", () => {
    expect(parseCitations("[[ref:bad 正文[[ref:checkup.ogtt|糖耐量]]")).toEqual([
      { kind: "text", text: "[[ref:bad 正文" },
      { kind: "ref", id: "checkup.ogtt", title: "糖耐量" },
    ]);
  });
});

describe("parseCitations：流式中写到一半的标记", () => {
  it("错误编号后接正文时不隐藏正文", () => {
    for (const tail of ["[[ref:checkup.ogtt 这段正文应保留", "[[record:0b6c1a2e 之后是正文", "[[ref:bad id|正文"]) {
      expect(parseCitations(`前文${tail}`)).toEqual([{ kind: "text", text: `前文${tail}` }]);
    }
    expect(parseCitations(`前文[[record: ${RECORD_ID} |产检`)).toEqual([
      { kind: "text", text: "前文" }, { kind: "text", text: "产检" },
    ]);
  });
  it("编号还没写完时整段隐藏", () => {
    expect(parseCitations("前文[[ref:che")).toEqual([{ kind: "text", text: "前文" }]);
    expect(parseCitations("前文[[record:0b6c1a2e-11")).toEqual([{ kind: "text", text: "前文" }]);
  });

  it("编号前带空白时也先隐藏", () => {
    expect(parseCitations("前文[[ref: che")).toEqual([{ kind: "text", text: "前文" }]);
  });

  it("已写出标题时只显示标题文字，不成胶囊", () => {
    expect(parseCitations("前文[[ref:checkup.ogtt|糖耐")).toEqual([
      { kind: "text", text: "前文" },
      { kind: "text", text: "糖耐" },
    ]);
  });

  it("末尾的标记前缀先隐藏", () => {
    for (const tail of ["[", "[[", "[[r", "[[re", "[[ref", "[[ref:", "[[rec", "[[reco", "[[recor", "[[record", "[[record:"]) {
      expect(parseCitations(`前文${tail}`), tail).toEqual([{ kind: "text", text: "前文" }]);
    }
  });

  it("不影响前面已闭合的合法引用", () => {
    expect(parseCitations("见[[ref:checkup.ogtt|糖耐量]]，还有[[record:0b6c")).toEqual([
      { kind: "text", text: "见" },
      { kind: "ref", id: "checkup.ogtt", title: "糖耐量" },
      { kind: "text", text: "，还有" },
    ]);
  });

  it("只有写到一半的标记时什么都不显示", () => {
    expect(parseCitations("[[ref:che")).toEqual([]);
  });
});


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

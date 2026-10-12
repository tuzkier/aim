// 测试专用合成图：swift scripts/ios/create-report-fixture.swift /tmp/aim-report-fixture.png
// 用 simctl addmedia 把输出导入目标模拟器，再运行照片报告 UI 用例。
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "/tmp/aim-report-fixture.png"
let formatter = DateFormatter()
formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
formatter.dateFormat = "yyyy-MM-dd"
let image = NSImage(size: NSSize(width: 1000, height: 1200))
image.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: 1000, height: 1200).fill()
let lines = [
    "合成验收报告 · 无真实患者资料", "验收测试医院（虚构）", "产检报告",
    "日期：\(formatter.string(from: .now))", "体重：62.5 kg", "收缩压：118 mmHg",
    "舒张压：76 mmHg", "空腹血糖：4.9 mmol/L", "血红蛋白：112 g/L",
    "胎心率：140 次/分", "尿蛋白：+    标记：↑    参考：阴性", "医嘱：按医生安排复查",
]
for (index, line) in lines.enumerated() {
    (line as NSString).draw(at: NSPoint(x: 55, y: 1100 - index * 84), withAttributes: [
        .font: NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.black,
    ])
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

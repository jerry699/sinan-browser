import Foundation

// Chrome's native messaging host for the 司南 menu extension (SinanMenuBridge): Chrome
// launches this per request and speaks one framed JSON message over stdio. The request
// lands as a pending file in the browser's data folder; a distributed notification tells
// the running 司南 to pick it up. The reply frame is empty-but-valid, so the extension's
// sendNativeMessage callback closes cleanly.
//
// The data folder arrives as --dir=<path> in the host manifest's args.

let dir = CommandLine.arguments.first(where: { $0.hasPrefix("--dir=") }).map { String($0.dropFirst(6)) }
    ?? (NSHomeDirectory() + "/Library/Application Support/司南")

func readFrame(from handle: FileHandle) -> Data? {
    let header = handle.readData(ofLength: 4)
    guard header.count == 4 else { return nil }
    let length = header.withUnsafeBytes { $0.load(as: UInt32.self) }
    guard length > 0, length < 64 * 1024 * 1024 else { return nil }
    let body = handle.readData(ofLength: Int(length))
    return body.count == Int(length) ? body : nil
}

func writeFrame(_ text: String, to handle: FileHandle) {
    var body = Data(text.utf8)
    var length = UInt32(body.count)
    let header = withUnsafeBytes(of: &length) { Data($0) }
    handle.write(header)
    handle.write(body)
}

let input = FileHandle.standardInput
guard let request = readFrame(from: input) else { exit(0) }

let fm = FileManager.default
let pending = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("native-messages", isDirectory: true)
try? fm.createDirectory(at: pending, withIntermediateDirectories: true)
let file = pending.appendingPathComponent(UUID().uuidString + ".json")
try? request.write(to: file, options: .atomic)

DistributedNotificationCenter.default().post(name: Notification.Name("com.sinan.nativeMessage"), object: nil)

writeFrame("{\"ok\":true}", to: FileHandle.standardOutput)
exit(0)

import Foundation

func logDebug(_ message: String) {
    let logFile = "/tmp/roocast-events.log"
    let msg = "\(message)\n"
    if let data = msg.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: logFile) {
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: logFile))
        }
    }
}

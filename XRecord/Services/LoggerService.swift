import Foundation
import os.log

// MARK: - 日志服务

class LoggerService {
    static let shared = LoggerService()

    private let logDirectory: URL
    private let logFile: URL
    private let dateFormatter: DateFormatter
    private let fileManager = FileManager.default

    private init() {
        // 隐藏目录：~/.xrecord/logs/
        let homeDir = fileManager.homeDirectoryForCurrentUser
        logDirectory = homeDir.appendingPathComponent(".xrecord/logs", isDirectory: true)
        logFile = logDirectory.appendingPathComponent("xrecord.log")

        // 日期格式化
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "zh_CN")

        // 创建日志目录
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 日志方法

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log("INFO", message: message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log("WARN", message: message, file: file, function: function, line: line)
    }

    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log("ERROR", message: fullMessage, file: file, function: function, line: line)
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        log("DEBUG", message: message, file: file, function: function, line: line)
        #endif
    }

    // MARK: - 内部日志写入

    private func log(_ level: String, message: String, file: String, function: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logLine = "[\(timestamp)] [\(level)] [\(fileName):\(line)] \(message)"

        // 打印到控制台
        print(logLine)

        // 写入文件
        writeToFile(logLine)
    }

    private func writeToFile(_ line: String) {
        let lineWithNewline = line + "\n"

        if fileManager.fileExists(atPath: logFile.path) {
            // 追加写入
            if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                fileHandle.seekToEndOfFile()
                if let data = lineWithNewline.data(using: .utf8) {
                    fileHandle.write(data)
                }
                try? fileHandle.close()
            }
        } else {
            // 首次创建
            try? lineWithNewline.write(to: logFile, atomically: true, encoding: .utf8)
        }

        // 限制日志文件大小（保留最近 1MB）
        trimLogIfNeeded()
    }

    // MARK: - 日志管理

    /// 限制日志文件大小
    private func trimLogIfNeeded() {
        let maxSize: UInt64 = 1024 * 1024 // 1MB

        guard let attrs = try? fileManager.attributesOfItem(atPath: logFile.path),
              let size = attrs[.size] as? UInt64,
              size > maxSize else { return }

        // 读取文件，保留后半部分
        if let content = try? String(contentsOf: logFile, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n")
            let halfIndex = lines.count / 2
            let trimmedLines = Array(lines[halfIndex...])
            let trimmedContent = trimmedLines.joined(separator: "\n")
            try? trimmedContent.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    /// 获取日志文件路径
    var logPath: String {
        logFile.path
    }

    /// 打开日志文件夹
    func openLogFolder() {
        NSWorkspace.shared.open(logDirectory)
    }
}

// MARK: - 全局便捷方法

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    LoggerService.shared.info(message, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    LoggerService.shared.warning(message, file: file, function: function, line: line)
}

func logError(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    LoggerService.shared.error(message, error: error, file: file, function: function, line: line)
}

#if DEBUG
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    LoggerService.shared.debug(message, file: file, function: function, line: line)
}
#else
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {}
#endif

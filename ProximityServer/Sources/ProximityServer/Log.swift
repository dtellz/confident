import Foundation

/// Small logger that writes to stdout with a timestamp and category, so output
/// shows up in the terminal where `swift run` was launched. Also writes to
/// stderr for `error` so it's visible even if stdout is redirected.
enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: " INFO", category: category, message: message())
    }

    static func debug(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: "DEBUG", category: category, message: message())
    }

    static func warn(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: " WARN", category: category, message: message())
    }

    static func error(_ category: String, _ message: @autoclosure () -> String) {
        let line = format(level: "ERROR", category: category, message: message())
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private static func emit(level: String, category: String, message: String) {
        print(format(level: level, category: category, message: message))
    }

    private static func format(level: String, category: String, message: String) -> String {
        "\(formatter.string(from: Date())) [\(level)] [\(category)] \(message)"
    }
}

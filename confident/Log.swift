import Foundation

/// Small logger that prints to stdout with a timestamp and category, so output
/// is visible in Xcode's console regardless of os_log filtering.
enum Log {
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    nonisolated static func info(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: " INFO", category: category, message: message())
    }

    nonisolated static func debug(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: "DEBUG", category: category, message: message())
    }

    nonisolated static func warn(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: " WARN", category: category, message: message())
    }

    nonisolated static func error(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: "ERROR", category: category, message: message())
    }

    private nonisolated static func emit(level: String, category: String, message: String) {
        print("\(formatter.string(from: Date())) [\(level)] [\(category)] \(message)")
    }
}

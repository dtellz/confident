import Foundation

let args = CommandLine.arguments

print("=========================================================")
print(" ProximityServer")
print("=========================================================")
Log.info("Boot", "PID=\(ProcessInfo.processInfo.processIdentifier) host=\(Host.current().localizedName ?? "?")")
Log.info("Boot", "Executable=\(CommandLine.arguments.first ?? "?")")

// Backend selection. An explicit URL on the command line always wins. With no
// argument we auto-detect among the known local ports (LM Studio 1234,
// llama.cpp 8080, MLX 8000) and pick the first one that's actually serving a
// model — so switching from LM Studio to MLX needs no flags. The iOS app can
// also re-point the backend at runtime via its settings menu.
let baseURL: URL
let model: String
if args.count > 1, let explicit = URL(string: args[1]) {
    baseURL = explicit
    model = args.count > 2 ? args[2] : "local-model"
    Log.info("Boot", "Backend (explicit): \(baseURL.absoluteString)")
} else {
    let detected = BackendDetector.detectAllBlocking()
    if let online = detected.first(where: { $0.online }) {
        baseURL = URL(string: "http://localhost:\(online.port)")!
        model = online.model ?? "local-model"
        Log.info("Boot", "Backend (auto-detected): \(online.name) on port \(online.port)")
    } else {
        baseURL = URL(string: "http://localhost:8000")!
        model = "local-model"
        Log.warn("Boot", "No local backend detected on known ports; defaulting to \(baseURL.absoluteString)")
    }
}
Log.info("Boot", "Backend model:      \(model)")
Log.info("Boot", "Multipeer service:  \(ChatProtocol.serviceType)")

let transport = MultipeerServer()
let llm = LMStudioClient(configuration: .init(baseURL: baseURL, model: model))
let session = ChatSession(transport: transport, llm: llm)

transport.start()
Log.info("Boot", "Ready. Open the iOS app to connect.")
print("---------------------------------------------------------")

Task { await session.run() }

RunLoop.main.run()

import Foundation

let args = CommandLine.arguments
let baseURL = (args.count > 1 ? URL(string: args[1]) : nil) ?? URL(string: "http://localhost:1234")!
let model = args.count > 2 ? args[2] : "local-model"

print("=========================================================")
print(" ProximityServer")
print("=========================================================")
Log.info("Boot", "PID=\(ProcessInfo.processInfo.processIdentifier) host=\(Host.current().localizedName ?? "?")")
Log.info("Boot", "Executable=\(CommandLine.arguments.first ?? "?")")
Log.info("Boot", "LM Studio base URL: \(baseURL.absoluteString)")
Log.info("Boot", "LM Studio model:    \(model)")
Log.info("Boot", "Multipeer service:  \(ChatProtocol.serviceType)")

let transport = MultipeerServer()
let llm = LMStudioClient(configuration: .init(baseURL: baseURL, model: model))
let session = ChatSession(transport: transport, llm: llm)

transport.start()
Log.info("Boot", "Ready. Open the iOS app to connect.")
print("---------------------------------------------------------")

Task { await session.run() }

RunLoop.main.run()

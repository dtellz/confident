import Foundation

/// Probes local OpenAI-compatible LLM servers (LM Studio, llama.cpp, MLX) to
/// discover which known ports are serving a model right now. Detection runs on
/// the Mac because only it can reach these `localhost` ports — the iOS app asks
/// over Multipeer and renders the result.
enum BackendDetector {

    /// API key sent as a Bearer token to backends that require auth. omlx
    /// rejects unauthenticated requests with HTTP 401; LM Studio and llama.cpp
    /// ignore the header. Hardcoded for this personal setup.
    static let apiKey = "1337"

    struct ProbeResult: Sendable {
        let online: Bool
        /// First model id reported by `/v1/models`, if the server lists one.
        let model: String?
    }

    /// Probe a single port on localhost. Returns `online == false` on any
    /// failure (refused connection, timeout, non-2xx, unparseable body).
    static func probe(port: Int, timeout: TimeInterval = 1.5) async -> ProbeResult {
        guard let url = URL(string: "http://localhost:\(port)/v1/models") else {
            return ProbeResult(online: false, model: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return ProbeResult(online: false, model: nil)
            }
            let model = (try? JSONDecoder().decode(ModelsResponse.self, from: data))?.data.first?.id
            return ProbeResult(online: true, model: model)
        } catch {
            return ProbeResult(online: false, model: nil)
        }
    }

    /// Probe every known backend (plus an optional extra/custom port) concurrently
    /// and return their statuses sorted by port.
    static func detectAll(extraPort: Int? = nil) async -> [ChatProtocol.BackendStatus] {
        var targets = ChatProtocol.knownBackends
        if let extra = extraPort, !targets.contains(where: { $0.port == extra }) {
            targets.append(ChatProtocol.KnownBackend(name: "Custom", port: extra))
        }
        return await withTaskGroup(of: ChatProtocol.BackendStatus.self) { group in
            for backend in targets {
                group.addTask {
                    let result = await probe(port: backend.port)
                    return ChatProtocol.BackendStatus(
                        name: backend.name,
                        port: backend.port,
                        online: result.online,
                        model: result.model
                    )
                }
            }
            var statuses: [ChatProtocol.BackendStatus] = []
            for await status in group { statuses.append(status) }
            return statuses.sorted { $0.port < $1.port }
        }
    }

    /// Synchronous wrapper for boot-time auto-detection in `main` (which runs
    /// before any async context). Blocks the calling thread until done.
    static func detectAllBlocking(extraPort: Int? = nil) -> [ChatProtocol.BackendStatus] {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task {
            box.value = await detectAll(extraPort: extraPort)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    private final class ResultBox: @unchecked Sendable {
        var value: [ChatProtocol.BackendStatus] = []
    }

    private struct ModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }
}

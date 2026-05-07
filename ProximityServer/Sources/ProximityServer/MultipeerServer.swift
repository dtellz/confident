import Foundation
@preconcurrency import MultipeerConnectivity

/// Advertises a Multipeer service and accepts incoming invitations from nearby
/// iOS clients. Decoded frames per-peer are exposed on `events`. Outbound
/// frames are sent via `send(_:to:)`.
final class MultipeerServer: NSObject, @unchecked Sendable {

    enum Event: Sendable {
        case connected(MCPeerID)
        case disconnected(MCPeerID)
        case frame(MCPeerID, ChatProtocol.ClientFrame)
    }

    enum TransportError: Error {
        case peerNotConnected
        case encodingFailed
    }

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let serviceType: String

    private let eventContinuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var heartbeatTask: Task<Void, Never>?

    init(displayName: String = Host.current().localizedName ?? "Mac",
         serviceType: String = ChatProtocol.serviceType) {
        self.serviceType = serviceType
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: myPeerID,
                                 securityIdentity: nil,
                                 encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                    discoveryInfo: ["role": "server"],
                                                    serviceType: serviceType)

        var cont: AsyncStream<Event>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.eventContinuation = cont

        super.init()
        session.delegate = self
        advertiser.delegate = self

        Log.info("Multipeer", "Configured advertiser displayName=\"\(displayName)\" service=\"\(serviceType)\" encryption=required")
    }

    func start() {
        advertiser.startAdvertisingPeer()
        Log.info("Multipeer", "startAdvertisingPeer() called — waiting for invitations")
        startHeartbeat()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        Log.info("Multipeer", "Advertising stopped, session disconnected")
    }

    func send(_ frame: ChatProtocol.ServerFrame, to peer: MCPeerID) throws {
        guard session.connectedPeers.contains(peer) else {
            Log.warn("Multipeer", "send() called but peer \(peer.displayName) is not connected")
            throw TransportError.peerNotConnected
        }
        let data: Data
        do {
            data = try encoder.encode(frame)
        } catch {
            Log.error("Multipeer", "Encode failure: \(error)")
            throw TransportError.encodingFailed
        }
        try session.send(data, toPeers: [peer], with: .reliable)
        Log.debug("Multipeer", "Sent \(data.count) bytes to \(peer.displayName) [frame=\(frameSummary(frame))]")
    }

    private func frameSummary(_ frame: ChatProtocol.ServerFrame) -> String {
        switch frame {
        case .token(let c): return "token(\(c.count) chars)"
        case .done: return "done"
        case .title(let t): return "title(\"\(t)\")"
        case .error(let m): return "error(\"\(m)\")"
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                let connected = self.session.connectedPeers.map(\.displayName).joined(separator: ", ")
                let count = self.session.connectedPeers.count
                Log.debug("Multipeer", "heartbeat — connected peers: \(count)\(count > 0 ? " [\(connected)]" : "")")
            }
        }
    }

    deinit { eventContinuation.finish() }
}

// MARK: - MCSessionDelegate

extension MultipeerServer: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .notConnected:
            Log.info("Multipeer", "Session → notConnected for \(peerID.displayName)")
            eventContinuation.yield(.disconnected(peerID))
        case .connecting:
            Log.info("Multipeer", "Session → connecting for \(peerID.displayName)")
        case .connected:
            Log.info("Multipeer", "Session → CONNECTED for \(peerID.displayName) ✓")
            eventContinuation.yield(.connected(peerID))
        @unknown default:
            Log.warn("Multipeer", "Session → unknown state for \(peerID.displayName)")
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Log.debug("Multipeer", "Received \(data.count) bytes from \(peerID.displayName)")
        do {
            let frame = try decoder.decode(ChatProtocol.ClientFrame.self, from: data)
            switch frame {
            case .chat(let history):
                let last = history.last?.content ?? ""
                let images = history.last?.images?.count ?? 0
                let imgSuffix = images > 0 ? " + \(images) image(s)" : ""
                Log.info("Multipeer", "Frame ← \(peerID.displayName): chat(\(history.count) turns)\(imgSuffix) — last=\"\(last.prefix(80))\(last.count > 80 ? "…" : "")\"")
            case .generateTitle(let history):
                Log.info("Multipeer", "Frame ← \(peerID.displayName): generateTitle(\(history.count) turns)")
            }
            eventContinuation.yield(.frame(peerID, frame))
        } catch {
            Log.error("Multipeer", "Decode failure from \(peerID.displayName): \(error). Raw=\(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
        }
    }

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        Log.debug("Multipeer", "didReceiveCertificate from \(peerID.displayName) — auto-accepting")
        certificateHandler(true)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer peerID: MCPeerID, at: URL?, withError: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerServer: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let ctxLen = context?.count ?? 0
        Log.info("Multipeer", "Invitation ← \(peerID.displayName) [context=\(ctxLen) bytes] — accepting")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Log.error("Multipeer", "Advertiser failed to start: \(error)")
    }
}

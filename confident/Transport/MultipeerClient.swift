import Foundation
@preconcurrency import MultipeerConnectivity

/// Browses for and maintains an encrypted Multipeer session with a single nearby
/// macOS peer. Decoded inbound frames arrive on `frames`; outbound frames are
/// sent via `send(_:)`. Connection state is published on `state`.
nonisolated final class MultipeerClient: NSObject, @unchecked Sendable {

    enum ConnectionState: Equatable, Sendable {
        case idle
        case browsing
        case connecting(peerName: String)
        case connected(peerName: String)
    }

    enum TransportError: Error {
        case notConnected
        case encodingFailed
    }

    private let serviceType: String
    private let myPeerID: MCPeerID
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser

    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    let state: AsyncStream<ConnectionState>

    private let frameContinuation: AsyncStream<ChatProtocol.ServerFrame>.Continuation
    let frames: AsyncStream<ChatProtocol.ServerFrame>

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var heartbeatTask: Task<Void, Never>?
    private var discoveredCount: Int = 0
    private var invitedCount: Int = 0

    init(displayName: String,
         serviceType: String = ChatProtocol.serviceType) {
        self.serviceType = serviceType
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: myPeerID,
                                 securityIdentity: nil,
                                 encryptionPreference: .required)
        self.browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)

        var sCont: AsyncStream<ConnectionState>.Continuation!
        self.state = AsyncStream { sCont = $0 }
        self.stateContinuation = sCont

        var fCont: AsyncStream<ChatProtocol.ServerFrame>.Continuation!
        self.frames = AsyncStream { fCont = $0 }
        self.frameContinuation = fCont

        super.init()

        session.delegate = self
        browser.delegate = self
        Log.info("Multipeer", "Configured browser displayName=\"\(displayName)\" service=\"\(serviceType)\" encryption=required")
        stateContinuation.yield(.idle)
    }

    func start() {
        browser.startBrowsingForPeers()
        stateContinuation.yield(.browsing)
        Log.info("Multipeer", "startBrowsingForPeers() called — searching for service \"\(serviceType)\"")
        startHeartbeat()
    }

    func stop() {
        browser.stopBrowsingForPeers()
        session.disconnect()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        stateContinuation.yield(.idle)
        Log.info("Multipeer", "Stopped browsing and disconnected")
    }

    func send(_ frame: ChatProtocol.ClientFrame) throws {
        guard !session.connectedPeers.isEmpty else {
            Log.warn("Multipeer", "send() called with no connected peers")
            throw TransportError.notConnected
        }
        let data: Data
        do {
            data = try encoder.encode(frame)
        } catch {
            Log.error("Multipeer", "Encode failure: \(error)")
            throw TransportError.encodingFailed
        }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        Log.debug("Multipeer", "Sent \(data.count) bytes to \(session.connectedPeers.count) peer(s)")
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                let connected = self.session.connectedPeers.count
                Log.debug("Multipeer", "heartbeat — discovered=\(self.discoveredCount) invited=\(self.invitedCount) connected=\(connected)")
            }
        }
    }

    deinit {
        stateContinuation.finish()
        frameContinuation.finish()
    }
}

// MARK: - MCSessionDelegate

nonisolated extension MultipeerClient: MCSessionDelegate {

    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        switch state {
        case .connecting:
            Log.info("Multipeer", "Session → connecting for \(peerID.displayName)")
            stateContinuation.yield(.connecting(peerName: peerID.displayName))
        case .connected:
            Log.info("Multipeer", "Session → CONNECTED for \(peerID.displayName) ✓")
            stateContinuation.yield(.connected(peerName: peerID.displayName))
        case .notConnected:
            Log.info("Multipeer", "Session → notConnected for \(peerID.displayName); resume browsing")
            stateContinuation.yield(.browsing)
        @unknown default:
            Log.warn("Multipeer", "Session → unknown state for \(peerID.displayName)")
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Log.debug("Multipeer", "Received \(data.count) bytes from \(peerID.displayName)")
        do {
            let frame = try decoder.decode(ChatProtocol.ServerFrame.self, from: data)
            frameContinuation.yield(frame)
        } catch {
            Log.error("Multipeer", "Decode failure: \(error). Raw=\(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
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

// MARK: - MCNearbyServiceBrowserDelegate

nonisolated extension MultipeerClient: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        discoveredCount += 1
        Log.info("Multipeer", "Discovered peer \(peerID.displayName) info=\(info ?? [:]) — inviting (timeout=30s)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        invitedCount += 1
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Log.info("Multipeer", "Lost peer \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Log.error("Multipeer", "Browser failed to start: \(error)")
    }
}

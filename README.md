# Confident

A proximity-based offline chatbot. The iOS app is a SwiftUI chat client; the
macOS server runs an LLM locally via [LM Studio](https://lmstudio.ai). The two
sides find each other over **Multipeer Connectivity** (Bluetooth + peer-to-peer
Wi-Fi), so no internet, router, or external services are required.

```
┌──────────┐     Multipeer (encrypted)      ┌──────────────┐     localhost      ┌────────────┐
│  iOS app │ ◄────────────────────────────► │ macOS server │ ◄────────────────► │ LM Studio  │
│ (SwiftUI)│         JSON frames            │ (swift run)  │   /v1/chat (SSE)   │ (local)    │
└──────────┘                                └──────────────┘                    └────────────┘
```

## Layout

```
confident/
├── confident.xcodeproj/                # iOS app (SwiftUI)
├── confident/                          # iOS sources (auto-synced into the target)
│   ├── confidentApp.swift              # @main
│   ├── Models/ChatMessage.swift
│   ├── Protocol/ChatProtocol.swift     # wire format
│   ├── Transport/MultipeerClient.swift # MCSession + browser
│   ├── ViewModels/ChatViewModel.swift  # @Observable, MainActor
│   └── Views/                          # ChatView, MessageBubble, status, typing
└── ProximityServer/                    # macOS Swift Package (`swift run`)
    ├── Package.swift
    └── Sources/ProximityServer/
        ├── main.swift                  # entry point
        ├── ChatProtocol.swift          # mirror of iOS wire format
        ├── MultipeerServer.swift       # MCSession + advertiser
        ├── LMStudioClient.swift        # SSE streaming HTTP client
        └── ChatSession.swift           # per-peer history + orchestration
```

The wire protocol is defined identically on both sides (`ChatProtocol.swift`).
Each frame is one JSON object sent as a single Multipeer payload:

* Client → Server: `{"type":"message","content":"…"}`
* Server → Client: `{"type":"token","content":"…"}` then `{"type":"done"}`
  (or `{"type":"error","message":"…"}` on failure)

## Run the macOS server

1. Install LM Studio, download a model, and click **Start Server** (default port
   `1234`). LM Studio's OpenAI-compatible endpoint is at
   `http://localhost:1234/v1/chat/completions`.
2. From the repo root:
   ```sh
   swift run --package-path ProximityServer
   # or with a custom URL/model:
   swift run --package-path ProximityServer http://localhost:1234 my-model
   ```
   You should see `Advertising over Multipeer. Waiting for iOS client…`.

The first run may prompt for **Local Network** access — accept it, otherwise
Multipeer cannot advertise.

## Run the iOS app

1. Open `confident.xcodeproj` in Xcode.
2. Pick a real device or a recent simulator and **Run**.
3. On first launch iOS will prompt for **Local Network** permission — accept.

The app browses for the Mac automatically and auto-invites it. The status pill
in the toolbar shows the live connection state (Searching → Connecting →
Connected). Once connected, type a message and the response streams in token by
token.

## Multi-turn, multi-peer

* The server keeps a per-peer chat history keyed by `MCPeerID`, so multiple iOS
  clients can chat independently without context bleed.
* If a peer disconnects mid-stream the in-flight task is cancelled and history
  is dropped on reconnect.
* If the user fires a new message while the previous response is still
  streaming, the older task is cancelled so token order stays coherent.

## Notes / troubleshooting

* **Bonjour service type** is `prox-chat`. The iOS target ships
  `_prox-chat._tcp` and `_prox-chat._udp` in `NSBonjourServices` plus an
  `NSLocalNetworkUsageDescription`; both are required on iOS 14+.
* **Encryption**: `MCSession` is created with `.required` on both sides.
* **Same Apple ID / proximity**: Multipeer works best when both devices are
  awake, unlocked, and physically close. It uses Bluetooth and AWDL; airplane
  mode disables it.
* **LM Studio model name**: when only one model is loaded, LM Studio accepts
  any string for `model`. The default is `local-model`; override via the second
  CLI arg.
* **Both Swift sources of `ChatProtocol`** must change together. They're kept
  separate so each project compiles standalone — there is no shared package.

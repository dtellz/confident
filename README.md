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

## Security model — read this before deploying

**This project is intended for personal use only.** It is a hobby/reference
implementation of Multipeer Connectivity + a local LLM, not a hardened product.
The defaults trade authentication for convenience, and you should understand
the tradeoff before exposing it to anyone but yourself.

### What is protected

* **End-to-end encryption.** `MCSession` is created with
  `MCEncryptionPreference.required`, so every byte between iOS and macOS is
  encrypted via DTLS. A nearby attacker sniffing the air sees ciphertext only.
* **No internet egress.** The transport is peer-to-peer (AWDL / Wi-Fi /
  Bluetooth), and the LLM runs locally in LM Studio. Your prompts and the
  model's responses never leave the two devices.
* **Short physical range.** Multipeer only operates within ~10–30 m. An
  attacker has to be physically nearby — they cannot reach you over the
  internet.
* **No code-execution surface.** Inbound frames are decoded into a small
  `Codable` enum. There is no `eval`, no shell-out, no file-path handling.

### What is **not** protected

* **No peer authentication.** The server auto-accepts every Multipeer
  invitation and auto-trusts every peer certificate (`certificateHandler(true)`).
  Anyone within range who knows the Bonjour service type (`prox-chat`, which is
  visible in the broadcast) can connect.
* **No rate limit.** A peer can fire requests at the LLM as fast as they want.
* **No payload size cap.** A peer could send a very large JSON blob; the
  decoder would attempt to buffer it before failing.
* **The macOS binary is unsigned and unsandboxed.** `swift run` produces a
  debug binary running with your full user privileges.

### What's the practical worst case if a stranger connects?

**They get to use your LLM for free.** That's it. Concretely:

* They can send arbitrary text and receive the model's responses, consuming
  your CPU/GPU and electricity for as long as they're in range.
* They can prompt-inject the model the same way you can — i.e. they get the
  same chat box you have.

What they **cannot** do, given the code in this repo:

* Read files, run shell commands, or otherwise touch your filesystem — the
  server only parses JSON and proxies HTTP to `localhost:1234`.
* Read your chat history. State is per-peer and in-memory only; nothing is
  persisted, and one peer cannot see another peer's conversation.
* Reach beyond `localhost:1234` on your Mac — the LM Studio URL is the only
  network destination the server ever opens.
* Persist anything between sessions — disconnect drops all per-peer state.
* Eavesdrop on your own conversations — DTLS protects the wire even from
  other authenticated peers.

So: realistic attacker payoff ≈ "free LLM tokens at your expense." That's
unwelcome but not catastrophic. If the threat model is just "someone in my
apartment building might mess with this," the practical exposure is small.

### When to harden this

Treat the defaults as "fine for me on my couch" and **not** as something to
expose in any of these situations:

* A coffee shop, library, or open-plan office.
* A device that handles privileged data, even indirectly (e.g., a Mac that
  also has SSH keys, source code, browser sessions).
* Any deployment where multiple users could plausibly be in physical range.

If any of those apply, the minimum hardening I'd recommend before turning it
on is:

1. **Per-peer authorization.** Pass a shared secret in `withContext:` on the
   client `invitePeer` call, validate it in the server's
   `didReceiveInvitationFromPeer` callback, and reject mismatches.
2. **Pinned certificate trust.** Replace the auto-accept in
   `didReceiveCertificate` with a TOFU check against a known certificate fingerprint.
3. **Caps and limits.** Reject inbound frames over ~64 KB; rate-limit messages
   per peer; cap concurrent in-flight requests.
4. **Sign and notarize the macOS binary** if you're distributing it.

None of those are wired up by default. PRs welcome.

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

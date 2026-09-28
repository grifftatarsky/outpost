#if os(iOS)
    import CarpenterKit
    import CarpenterUI
    import Foundation
    import NearbyInteraction
    import Network
    import Observation

    @MainActor
    @Observable
    final class TapSwapper {
        private(set) var phase: TapSwap.Phase = .looking(closest: nil)
        private(set) var trouble: TapToSwapView.Trouble?
        @ObservationIgnored var onArrival: ((String) -> Void)?

        @ObservationIgnored private var swap: TapSwap
        private let name = UUID().uuidString
        @ObservationIgnored private var listener: NWListener?
        @ObservationIgnored private var browser: NWBrowser?
        @ObservationIgnored private var dialled: Set<String> = []
        @ObservationIgnored private var links: [TapPeer: NWConnection] = [:]
        @ObservationIgnored private var greeted: Set<TapPeer> = []
        @ObservationIgnored private var sessions: [TapPeer: NISession] = [:]
        private let watcher = SessionWatcher()
        @ObservationIgnored private var ticker: Task<Void, Never>?

        static let serviceType = "_tapswap._tcp"
        static let largestFrame = 65_536
        static let mostPhones = 8
        static let lingers: Duration = .seconds(180)
        private static let refusedByLocalNetworkPrivacy: Int32 = -65_570

        static var canMeasure: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

        init(handingOver code: String) {
            swap = TapSwap(handingOver: code)
        }

        var hasSwapped: Bool { swap.partner != nil }

        func start() {
            watcher.onDistance = { [weak self] session, distance in self?.measured(session, distance) }
            watcher.onEnd = { [weak self] session, refused in self?.ended(session, refused: refused) }
            listen()
            browse()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self else { return }
                    self.refresh()
                }
            }
        }

        func accept() {
            apply(swap.accept(at: .now))
        }

        func handOver(_ text: String) {
            apply(swap.handOver(text))
        }

        func stop() {
            ticker?.cancel()
            listener?.cancel()
            browser?.cancel()
            for link in links.values { link.cancel() }
            for session in sessions.values { session.invalidate() }
            listener = nil
            browser = nil
            links = [:]
            sessions = [:]
        }

        func keepOnlyThePartner() {
            listener?.cancel()
            browser?.cancel()
            listener = nil
            browser = nil
            for session in sessions.values { session.invalidate() }
            sessions = [:]
            for (peer, link) in links where peer != swap.partner {
                link.cancel()
                links[peer] = nil
            }
        }

        // MARK: Finding the other phone, over the local network and nothing else

        private var parameters: NWParameters {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            return parameters
        }

        private func listen() {
            guard let listener = try? NWListener(using: parameters) else { return }
            listener.service = NWListener.Service(name: name, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.adopt(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listening(changed: state) }
            }
            listener.start(queue: .main)
            self.listener = listener
        }

        private func browse() {
            let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                MainActor.assumeIsolated { self?.found(results) }
            }
            browser.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.browsing(changed: state) }
            }
            browser.start(queue: .main)
            self.browser = browser
        }

        private func found(_ results: Set<NWBrowser.Result>) {
            for result in results {
                guard case .service(let theirs, _, _, _) = result.endpoint, name < theirs, !dialled.contains(theirs)
                else { continue }
                dialled.insert(theirs)
                adopt(NWConnection(to: result.endpoint, using: parameters))
            }
        }

        private func listening(changed state: NWListener.State) {
            switch state {
            case .waiting(let error), .failed(let error): noteRefusal(error)
            default: break
            }
        }

        private func browsing(changed state: NWBrowser.State) {
            switch state {
            case .ready where trouble == .noLocalNetwork: trouble = nil
            case .waiting(let error), .failed(let error): noteRefusal(error)
            default: break
            }
        }

        private func noteRefusal(_ error: NWError) {
            guard case .dns(let code) = error, code == Self.refusedByLocalNetworkPrivacy else { return }
            trouble = .noLocalNetwork
        }

        // MARK: One link per phone

        private func adopt(_ connection: NWConnection) {
            guard links.count < Self.mostPhones else { return connection.cancel() }
            let peer = TapPeer()
            links[peer] = connection
            connection.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.link(peer, changed: state) }
            }
            connection.start(queue: .main)
        }

        private func link(_ peer: TapPeer, changed state: NWConnection.State) {
            switch state {
            case .ready:
                guard greeted.insert(peer).inserted else { return }
                let session = NISession()
                session.delegate = watcher
                sessions[peer] = session
                guard let token = session.discoveryToken,
                    let archived = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                else {
                    drop(peer)
                    return
                }
                apply(swap.connected(peer, token: archived, at: .now))
                receive(from: peer)
            case .failed, .cancelled:
                drop(peer)
            default:
                break
            }
        }

        private func drop(_ peer: TapPeer) {
            links[peer]?.cancel()
            links[peer] = nil
            sessions[peer]?.invalidate()
            sessions[peer] = nil
            swap.disconnected(peer)
            refresh()
        }

        private func receive(from peer: TapPeer) {
            guard let connection = links[peer] else { return }
            connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard error == nil, let header, header.count == 4 else { return self.drop(peer) }
                    let length = header.reduce(0) { $0 << 8 | Int($1) }
                    guard length > 0, length <= Self.largestFrame else { return self.drop(peer) }
                    self.receive(length, from: peer)
                }
            }
        }

        private func receive(_ length: Int, from peer: TapPeer) {
            guard let connection = links[peer] else { return }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard error == nil, let body, body.count == length,
                        let message = try? JSONDecoder().decode(TapMessage.self, from: body)
                    else { return self.drop(peer) }
                    self.apply(self.swap.received(message, from: peer, at: .now))
                    self.receive(from: peer)
                }
            }
        }

        private func transmit(_ message: TapMessage, to peer: TapPeer) {
            guard let connection = links[peer], let body = try? JSONEncoder().encode(message),
                body.count <= Self.largestFrame
            else { return }
            let frame = withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) } + body
            connection.send(content: frame, completion: .contentProcessed { _ in })
        }

        // MARK: How far away it is

        private func range(_ peer: TapPeer, token: Data) {
            guard let session = sessions[peer],
                let theirs = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token)
            else { return }
            session.run(NINearbyPeerConfiguration(peerToken: theirs))
        }

        private func peer(measuredBy session: ObjectIdentifier) -> TapPeer? {
            sessions.first { ObjectIdentifier($0.value) == session }?.key
        }

        private func measured(_ session: ObjectIdentifier, _ distance: Double?) {
            guard let peer = peer(measuredBy: session) else { return }
            swap.measured(peer, distance: distance, at: .now)
            refresh()
        }

        private func ended(_ session: ObjectIdentifier, refused: Bool) {
            if refused { trouble = .notAllowed }
            guard let peer = peer(measuredBy: session) else { return }
            sessions[peer] = nil
            swap.measured(peer, distance: nil, at: .now)
            refresh()
        }

        // MARK: Doing what the swap says

        private func apply(_ effects: TapSwap.Effects) {
            for send in effects.sends { transmit(send.message, to: send.to) }
            for (peer, token) in effects.rangeWith { range(peer, token: token) }
            for arrival in effects.arrived { onArrival?(arrival) }
            refresh()
        }

        private func refresh() {
            let current = swap.phase(at: .now)
            if current != phase { phase = current }
        }
    }

    @MainActor
    private final class SessionWatcher: NSObject, NISessionDelegate {
        var onDistance: ((ObjectIdentifier, Double?) -> Void)?
        var onEnd: ((ObjectIdentifier, Bool) -> Void)?

        nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
            let measured = ObjectIdentifier(session)
            let distance = nearbyObjects.first?.distance.map(Double.init)
            MainActor.assumeIsolated { onDistance?(measured, distance) }
        }

        nonisolated func session(
            _ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason
        ) {
            let measured = ObjectIdentifier(session)
            MainActor.assumeIsolated { onDistance?(measured, nil) }
        }

        nonisolated func sessionSuspensionEnded(_ session: NISession) {
            if let configuration = session.configuration { session.run(configuration) }
        }

        nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
            let measured = ObjectIdentifier(session)
            let refused = (error as? NIError)?.code == .userDidNotAllow
            MainActor.assumeIsolated { onEnd?(measured, refused) }
        }
    }
#endif

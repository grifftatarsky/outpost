import Foundation
import Testing
import UserNotifications

@testable import CarpenterApp

@Suite("A push sets off a sync")
@MainActor
struct PushArrivalsTests {
    @Test("An arriving push runs the registered sync")
    func arrivalRunsTheHandler() async {
        let arrivals = PushArrivals()
        var synced = false

        arrivals.onArrival { synced = true }
        await arrivals.arrived()

        #expect(synced, "a push arrived and nothing fetched")
    }

    @Test("Arrival waits for the sync to finish, rather than returning once it has started")
    func arrivalAwaitsTheSync() async {
        let arrivals = PushArrivals()
        var finished = false

        arrivals.onArrival {
            try? await Task.sleep(for: .milliseconds(50))
            finished = true
        }
        await arrivals.arrived()

        #expect(finished, "the push was reported handled while its fetch was still in flight")
    }

    @Test("A push before anything is listening is harmless")
    func arrivalBeforeRegistrationIsHarmless() async {
        let arrivals = PushArrivals()

        #expect(!arrivals.isListening)
        await arrivals.arrived()

        arrivals.onArrival {}
        #expect(arrivals.isListening)
    }

    @Test("Registering again replaces the previous listener")
    func registeringAgainReplaces() async {
        let arrivals = PushArrivals()
        var oldRan = false
        var newRan = false

        arrivals.onArrival { oldRan = true }
        arrivals.onArrival { newRan = true }
        await arrivals.arrived()

        #expect(newRan)
        #expect(!oldRan, "a push reached a session that had been replaced")
    }

}

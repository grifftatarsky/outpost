@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "Two of Alice's devices approve her new laptop at once", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct TwoDevicesApproveOneLaptopTests {
    @Test(
        "Alice's phone and tablet both approve the laptop, and everyone lists it once and it reads Bob",
        arguments: [["Alice", "Alice's tablet"], ["Alice's tablet", "Alice"]])
    func bothApproveTheLaptop(approvers: [String]) async throws {
        let g = try await Gathering.of("Alice", "Bob")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob"])
        try await g.secondDevice("Alice's tablet", of: "Alice")
        let laptop = try await g.deviceWaitingForApproval("Alice's laptop", of: "Alice")
        let alices = ["Alice", "Alice's tablet", "Alice's laptop"]

        for approver in approvers {
            await g[approver].refreshDeviceSync()
            try await g.quiesce()
        }
        var requests: [DeviceRequest] = []
        for approver in approvers {
            let request = g[approver].deviceRequests.first { $0.device == laptop.pendingDevice?.id }
            requests.append(try #require(request, "precondition: \(approver) sees the laptop asking to join"))
        }
        for (approver, request) in zip(approvers, requests) {
            try await g[approver].approveDevice(request)
            try await g.quiesce()
        }
        try await g.takeApproval(on: "Alice's laptop")
        try await g.settle()
        try await g["Bob"].send("for the laptop", to: room)
        try await g.settle()

        for name in alices {
            #expect(g[name].devices.count == 3, "\(name) lists \(g[name].devices.count) devices for Alice")
            #expect(g[name].deviceRequests.isEmpty, "\(name) still shows a device asking to join")
        }
        #expect(g.devices(of: "Alice", seenBy: "Bob").count == 3, "Bob does not list Alice's three devices")
        for name in alices + ["Bob"] {
            #expect(
                g.devices(of: "Alice", seenBy: name) == Set(alices.map(g.device)),
                "\(name) does not list exactly Alice's phone, tablet and laptop")
        }
        #expect(g.shows("for the laptop", in: room, on: "Alice's laptop"), "Alice's laptop never read Bob's message")
        g.sameRoom(room, on: alices + ["Bob"])
    }
}

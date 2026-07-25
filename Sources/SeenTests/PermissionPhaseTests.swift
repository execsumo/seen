import Foundation
import SeenKit

let permissionPhaseTests: [TestCase] = [
    TestCase("permission phase: granted always returns granted") {
        let now = Date()
        try expectEqual(resolvePermissionPhase(granted: true, requestedAt: nil, now: now), .granted)
        try expectEqual(resolvePermissionPhase(granted: true, requestedAt: now.addingTimeInterval(-5), now: now), .granted)
    },
    
    TestCase("permission phase: not granted and never requested returns needed") {
        let now = Date()
        try expectEqual(resolvePermissionPhase(granted: false, requestedAt: nil, now: now), .needed)
    },
    
    TestCase("permission phase: requested 5s ago returns pending restart") {
        let now = Date()
        try expectEqual(resolvePermissionPhase(granted: false, requestedAt: now.addingTimeInterval(-5), now: now), .requestedPendingRestart)
    },
    
    TestCase("permission phase: requested 0.5s ago returns needed") {
        let now = Date()
        try expectEqual(resolvePermissionPhase(granted: false, requestedAt: now.addingTimeInterval(-0.5), now: now), .needed)
    },
    
    TestCase("permission phase: exact 2.0s threshold returns pending restart") {
        let now = Date()
        try expectEqual(resolvePermissionPhase(granted: false, requestedAt: now.addingTimeInterval(-2.0), now: now), .requestedPendingRestart)
    }
]

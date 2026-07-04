import Foundation
import SwiftUI
import SeenKit

public struct MenuBarIcon: View {
    let state: IconState
    
    public init(state: IconState) {
        self.state = state
    }
    
    public var body: some View {
        switch state {
        case .idle:
            Image(systemName: "eye")
        case .recentCapture:
            Image(systemName: "bolt.fill")
        case .sessionActive:
            Image(systemName: "record.circle")
        }
    }
}

public struct MenuBarIconContainer: View {
    var lastCapture: Date?
    var activeSessions: Int
    @State private var now = Date()
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    public init(lastCapture: Date?, activeSessions: Int) {
        self.lastCapture = lastCapture
        self.activeSessions = activeSessions
    }
    
    public var body: some View {
        MenuBarIcon(state: iconState(lastCapture: lastCapture, activeSessions: activeSessions, now: now))
            .onReceive(timer) { time in
                now = time
            }
    }
}

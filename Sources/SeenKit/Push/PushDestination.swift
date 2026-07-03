import Foundation

public enum PushDestination: Codable, Sendable, Equatable, Hashable {
    case commandTemplate(String)
    case tmuxPane(pane: String, template: String)
    case clipboard
}

import Foundation

/// How the user has classified an app or website for the productivity donut.
/// The absence of a tag means the time falls into "Other".
enum ProductivityTag: String, Codable {
    case productive
    case unproductive
}

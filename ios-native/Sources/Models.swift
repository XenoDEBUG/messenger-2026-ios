import Foundation

struct User: Codable, Identifiable, Hashable {
    var id: String { username }
    let username: String
    let displayName: String?
    let color: String?
    let avatar: String?
    let bio: String?
    let status: String?

    var name: String {
        if let d = displayName, !d.isEmpty { return d }
        return username
    }
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let chatType: String
    let chatId: String
    let from: String
    let to: String?
    let text: String
    let createdAt: Date
}

struct AuthResponse: Codable { let token: String; let user: User }
struct MeResponse: Codable { let user: User }
struct UserList: Codable { let users: [User] }
struct FriendsResponse: Codable { let friends: [String]; let incoming: [String]; let outgoing: [String] }
struct MessagesResponse: Codable { let messages: [Message] }
struct OkResponse: Codable { let ok: Bool? }

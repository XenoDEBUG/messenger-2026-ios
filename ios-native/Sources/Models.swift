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

struct ServerRole: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String
    let emoji: String
    let perms: [String]
}

struct ServerMember: Codable, Identifiable, Hashable {
    var id: String { username }
    let username: String
    let owner: Bool
    let roleIds: [String]
}

struct ServerChannel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let avatar: String?
}

struct GuildServer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let owner: String
    let avatar: String?
    let myPerms: [String]
    let inviteCode: String?
    let roles: [ServerRole]
    let members: [ServerMember]
    let channels: [ServerChannel]

    func can(_ perm: String) -> Bool { myPerms.contains(perm) }
}

struct AuthResponse: Codable { let token: String; let user: User }
struct MeResponse: Codable { let user: User }
struct UserList: Codable { let users: [User] }
struct FriendsResponse: Codable { let friends: [String]; let incoming: [String]; let outgoing: [String] }
struct MessagesResponse: Codable { let messages: [Message] }
struct ServersResponse: Codable { let servers: [GuildServer] }
struct JoinResponse: Codable { let ok: Bool?; let serverId: String? }

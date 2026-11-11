import Foundation
import SocketIO
import SwiftUI

@MainActor
final class Session: ObservableObject {
    @Published var token: String? = UserDefaults.standard.string(forKey: "token")
    @Published var me: User?
    @Published var friends: [User] = []
    @Published var incoming: [User] = []
    @Published var outgoing: [User] = []
    @Published var messages: [String: [Message]] = [:]   // ключ — username собеседника
    @Published var profiles: [String: User] = [:]
    @Published var error: String?

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    var isLoggedIn: Bool { token != nil && me != nil }

    func login(username: String, password: String, displayName: String, register: Bool) async {
        do {
            var body: [String: Any] = ["username": username, "password": password]
            if register { body["displayName"] = displayName }
            let r: AuthResponse = try await API.request("POST", register ? "/api/register" : "/api/login",
                                                        body: body, decode: AuthResponse.self)
            UserDefaults.standard.set(r.token, forKey: "token")
            token = r.token
            me = r.user
            await afterLogin()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // При запуске: если токен ещё действует, входим; при ошибке сети токен не сбрасываем
    func restore() async {
        guard let t = token, me == nil else { return }
        do {
            let r: MeResponse = try await API.request("GET", "/api/me", token: t, decode: MeResponse.self)
            me = r.user
            await afterLogin()
        } catch let e as APIError where e.status == 401 {
            logout()
        } catch {
            self.error = "Нет связи с сервером"
        }
    }

    func logout() {
        socket?.disconnect()
        socket = nil
        manager = nil
        UserDefaults.standard.removeObject(forKey: "token")
        token = nil
        me = nil
        friends = []; incoming = []; outgoing = []
        messages = [:]; profiles = [:]
    }

    private func afterLogin() async {
        await loadFriends()
        connectSocket()
    }

    func loadFriends() async {
        guard let t = token else { return }
        do {
            let f: FriendsResponse = try await API.request("GET", "/api/friends", token: t, decode: FriendsResponse.self)
            friends = try await fetchUsers(f.friends)
            incoming = try await fetchUsers(f.incoming)
            outgoing = try await fetchUsers(f.outgoing)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchUsers(_ names: [String]) async throws -> [User] {
        var out: [User] = []
        for n in names {
            let r: UserList = try await API.request("GET", "/api/users?q=" + n, token: token, decode: UserList.self)
            let u = r.users.first { $0.username == n }
                ?? User(username: n, displayName: nil, color: nil, avatar: nil, bio: nil, status: nil)
            profiles[n] = u
            out.append(u)
        }
        return out
    }

    func requestFriend(_ name: String) async { await friendAction("/api/friends/request", name) }
    func accept(_ name: String) async { await friendAction("/api/friends/accept", name) }

    private func friendAction(_ path: String, _ name: String) async {
        guard let t = token else { return }
        do {
            _ = try await API.request("POST", path, body: ["username": name], token: t, decode: OkResponse.self)
            await loadFriends()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMessages(_ peer: String) async {
        guard let t = token else { return }
        do {
            let r: MessagesResponse = try await API.request("GET", "/api/messages?chatType=dm&with=" + peer,
                                                            token: t, decode: MessagesResponse.self)
            messages[peer] = r.messages
            socket?.emit("messages:read", ["chatType": "dm", "with": peer])
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send(to peer: String, text: String) {
        guard let s = socket, s.status == .connected else {
            error = "Нет связи с сервером"
            return
        }
        s.emitWithAck("message:send", ["chatType": "dm", "to": peer, "text": text])
            .timingOut(after: 10) { [weak self] data in
                Task { @MainActor in
                    let first = data.first as? [String: Any]
                    guard let ok = first?["ok"] as? Bool, ok,
                          let m = first?["message"], let msg = Session.decodeMessage(m) else {
                        self?.error = (first?["error"] as? String) ?? "Сообщение не отправлено"
                        return
                    }
                    self?.receive(msg)
                }
            }
    }

    private func connectSocket() {
        guard let t = token else { return }
        socket?.disconnect()
        let m = SocketManager(socketURL: API.base, config: [.log(false), .compress])
        let s = m.defaultSocket
        s.on("message:new") { [weak self] data, _ in
            guard let raw = data.first, let msg = Session.decodeMessage(raw) else { return }
            Task { @MainActor in self?.receive(msg) }
        }
        s.on("friend:update") { [weak self] _, _ in
            Task { @MainActor in await self?.loadFriends() }
        }
        s.connect(withPayload: ["token": t])
        manager = m
        socket = s
    }

    private func receive(_ m: Message) {
        let peer = m.from == me?.username ? (m.to ?? "") : m.from
        guard !peer.isEmpty else { return }
        if messages[peer, default: []].contains(where: { $0.id == m.id }) { return }
        messages[peer, default: []].append(m)
    }

    nonisolated static func decodeMessage(_ any: Any) -> Message? {
        guard JSONSerialization.isValidJSONObject(any),
              let d = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? API.decoder.decode(Message.self, from: d)
    }
}

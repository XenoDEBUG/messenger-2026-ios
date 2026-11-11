import Foundation
import SocketIO
import SwiftUI
import WebRTC

// Ответ, который нам не нужен (сервер присылает {ok:true} или объект сервера)
struct Empty: Decodable {}

enum CallPhase { case idle, outgoing, incoming, connected }

private enum EndReason { case hangUp, remote }

@MainActor
final class Session: ObservableObject {
    @Published var token: String? = UserDefaults.standard.string(forKey: "token")
    @Published var me: User?
    @Published var friends: [User] = []
    @Published var incoming: [User] = []
    @Published var outgoing: [User] = []
    @Published var messages: [String: [Message]] = [:]        // ключ — username собеседника
    @Published var channelMessages: [String: [Message]] = [:] // ключ — id канала
    @Published var servers: [GuildServer] = []
    @Published var profiles: [String: User] = [:]
    @Published var error: String?

    // Звонок
    @Published var callPhase: CallPhase = .idle
    @Published var callPeer: User?
    @Published var callVideo = false
    @Published var callStart: Date?
    @Published var localVideo: RTCVideoTrack?
    @Published var remoteVideo: RTCVideoTrack?
    @Published var micOn = true
    @Published var camOn = true

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var engine: CallEngine?
    private var pendingOffer: String?
    private var pendingIce: [[String: Any]] = []

    var isLoggedIn: Bool { token != nil && me != nil }

    // MARK: Аккаунт

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
        engine?.close()
        engine = nil
        socket?.disconnect()
        socket = nil
        manager = nil
        UserDefaults.standard.removeObject(forKey: "token")
        token = nil
        me = nil
        friends = []; incoming = []; outgoing = []
        messages = [:]; channelMessages = [:]; profiles = [:]; servers = []
        callPhase = .idle; callPeer = nil; localVideo = nil; remoteVideo = nil
    }

    private func afterLogin() async {
        await loadFriends()
        await loadServers()
        connectSocket()
    }

    func updateProfile(displayName: String, bio: String, status: String, color: String?) async {
        guard let t = token else { return }
        var body: [String: Any] = ["displayName": displayName, "bio": bio, "status": status]
        if let c = color { body["color"] = c }
        do {
            let r: MeResponse = try await API.request("PATCH", "/api/me", body: body, token: t, decode: MeResponse.self)
            me = r.user
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Частичное обновление профиля (PATCH /api/me): имя, цвет, статус, картинки, ссылки
    func patchProfile(_ body: [String: Any]) async {
        guard let t = token else { return }
        do {
            let r: MeResponse = try await API.request("PATCH", "/api/me", body: body, token: t, decode: MeResponse.self)
            me = r.user
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Друзья

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
            _ = try await API.request("POST", path, body: ["username": name], token: t, decode: Empty.self)
            await loadFriends()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Личные сообщения

    func loadMessages(_ peer: String) async {
        guard let t = token else { return }
        do {
            let r: MessagesResponse = try await API.request("GET", "/api/messages?chatType=dm&with=" + peer,
                                                            token: t, decode: MessagesResponse.self)
            // Записи о звонках, которые есть только на этом устройстве, сохраняем
            let local = (messages[peer] ?? []).filter { $0.from == Session.callMarker }
            messages[peer] = (r.messages + local).sorted { $0.createdAt < $1.createdAt }
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
                Task { @MainActor in self?.handleSendAck(data) }
            }
    }

    // MARK: Серверы

    func loadServers() async {
        guard let t = token else { return }
        do {
            let r: ServersResponse = try await API.request("GET", "/api/servers", token: t, decode: ServersResponse.self)
            servers = r.servers
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Общая отправка изменений: после успеха список серверов перечитывается
    private func mutate(_ method: String, _ path: String, _ body: [String: Any]? = nil) async {
        guard let t = token else { return }
        do {
            _ = try await API.request(method, path, body: body, token: t, decode: Empty.self)
            await loadServers()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createServer(_ name: String) async { await mutate("POST", "/api/servers", ["name": name]) }
    func joinServer(code: String) async { await mutate("POST", "/api/servers/join", ["code": code]) }
    func leaveServer(_ id: String) async { await mutate("POST", "/api/servers/\(id)/leave") }
    func deleteServer(_ id: String) async { await mutate("DELETE", "/api/servers/\(id)") }
    func renameServer(_ id: String, _ name: String) async { await mutate("PATCH", "/api/servers/\(id)", ["name": name]) }
    func createChannel(_ sid: String, _ name: String) async { await mutate("POST", "/api/servers/\(sid)/channels", ["name": name]) }
    func deleteChannel(_ sid: String, _ chId: String) async { await mutate("DELETE", "/api/servers/\(sid)/channels/\(chId)") }

    func createRole(_ sid: String, name: String, color: String, emoji: String, perms: [String]) async {
        await mutate("POST", "/api/servers/\(sid)/roles",
                     ["name": name, "color": color, "emoji": emoji, "perms": perms])
    }

    func deleteRole(_ sid: String, _ rid: String) async { await mutate("DELETE", "/api/servers/\(sid)/roles/\(rid)") }

    func setMemberRoles(_ sid: String, user: String, roleIds: [String]) async {
        await mutate("PUT", "/api/servers/\(sid)/members/\(user)/roles", ["roleIds": roleIds])
    }

    func kick(_ sid: String, user: String) async { await mutate("DELETE", "/api/servers/\(sid)/members/\(user)") }

    // Код приглашения: сервер создаёт новый
    func regenerateInvite(_ sid: String) async { await mutate("POST", "/api/servers/\(sid)/invite") }

    // MARK: Каналы

    func openChannel(_ chId: String) async {
        guard let t = token else { return }
        socket?.emitWithAck("channel:join", chId).timingOut(after: 5) { _ in }
        do {
            let r: MessagesResponse = try await API.request("GET", "/api/messages?chatType=channel&chatId=" + chId,
                                                            token: t, decode: MessagesResponse.self)
            channelMessages[chId] = r.messages
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sendChannel(_ chId: String, text: String) {
        guard let s = socket, s.status == .connected else {
            error = "Нет связи с сервером"
            return
        }
        s.emitWithAck("message:send", ["chatType": "channel", "chatId": chId, "text": text])
            .timingOut(after: 10) { [weak self] data in
                Task { @MainActor in self?.handleSendAck(data) }
            }
    }

    private func handleSendAck(_ data: [Any]) {
        let first = data.first as? [String: Any]
        guard let ok = first?["ok"] as? Bool, ok,
              let m = first?["message"], let msg = Session.decodeMessage(m) else {
            error = (first?["error"] as? String) ?? "Сообщение не отправлено"
            return
        }
        receive(msg)
    }

    // MARK: Сокет

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
        s.on("servers:update") { [weak self] _, _ in
            Task { @MainActor in await self?.loadServers() }
        }
        s.on("call:invite") { [weak self] data, _ in
            guard let d = data.first as? [String: Any], let from = d["from"] as? String,
                  let sdp = (d["offer"] as? [String: Any])?["sdp"] as? String else { return }
            let video = d["video"] as? Bool ?? false
            Task { @MainActor in self?.onInvite(from: from, sdp: sdp, video: video) }
        }
        s.on("call:answer") { [weak self] data, _ in
            guard let d = data.first as? [String: Any], let from = d["from"] as? String,
                  let sdp = (d["answer"] as? [String: Any])?["sdp"] as? String else { return }
            Task { @MainActor in self?.onAnswer(from: from, sdp: sdp) }
        }
        s.on("call:ice") { [weak self] data, _ in
            guard let d = data.first as? [String: Any], let from = d["from"] as? String,
                  let cand = d["candidate"] as? [String: Any] else { return }
            Task { @MainActor in self?.onIce(from: from, candidate: cand) }
        }
        s.on("call:end") { [weak self] data, _ in
            guard let d = data.first as? [String: Any], let from = d["from"] as? String else { return }
            Task { @MainActor in self?.onRemoteEnd(from: from) }
        }

        s.connect(withPayload: ["token": t])
        manager = m
        socket = s
    }

    private func receive(_ m: Message) {
        if m.chatType == "channel" {
            var list = channelMessages[m.chatId] ?? []
            if list.contains(where: { $0.id == m.id }) { return }
            list.append(m)
            channelMessages[m.chatId] = list
            return
        }
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

    // MARK: Звонки

    static let callMarker = "__call__"

    private func emitDict(_ event: String, _ payload: [String: Any]) {
        socket?.emit(event, payload)
    }

    private func friendUser(_ name: String) -> User {
        friends.first { $0.username == name }
            ?? profiles[name]
            ?? User(username: name, displayName: nil, color: nil, avatar: nil, bio: nil, status: nil)
    }

    private func beginEngine(video: Bool) {
        let e = CallEngine(video: video)
        e.onCandidate = { [weak self] c in Task { @MainActor in self?.sendCandidate(c) } }
        e.onConnected = { [weak self] in Task { @MainActor in self?.connectedNow() } }
        e.onFailed = { [weak self] in Task { @MainActor in self?.finishCall(.hangUp) } }
        e.onRemoteVideo = { [weak self] t in Task { @MainActor in self?.remoteVideo = t } }
        engine = e
        e.setup()
        localVideo = e.localVideo
    }

    func startCall(to peer: User, video: Bool) {
        guard callPhase == .idle else { return }
        guard let s = socket, s.status == .connected else {
            error = "Нет связи с сервером"
            return
        }
        callPeer = peer
        callVideo = video
        callPhase = .outgoing
        beginEngine(video: video)
        engine?.makeOffer { [weak self] sdp in
            Task { @MainActor in
                self?.emitDict("call:invite", [
                    "to": peer.username,
                    "video": video,
                    "offer": ["type": "offer", "sdp": sdp] as [String: Any]
                ])
            }
        }
    }

    func acceptCall() {
        guard callPhase == .incoming, let peer = callPeer, let offer = pendingOffer else { return }
        pendingOffer = nil
        callPhase = .connected
        beginEngine(video: callVideo)
        engine?.acceptOffer(offer) { [weak self] sdp in
            Task { @MainActor in
                self?.emitDict("call:answer", [
                    "to": peer.username,
                    "answer": ["type": "answer", "sdp": sdp] as [String: Any]
                ])
            }
        }
        applyPendingIce()
    }

    func declineCall() {
        guard callPhase == .incoming else { return }
        hangUp()
    }

    func hangUp() {
        guard let peer = callPeer else { return }
        emitDict("call:end", ["to": peer.username])
        finishCall(.hangUp)
    }

    func toggleMic() {
        micOn.toggle()
        engine?.setMic(micOn)
    }

    func toggleCam() {
        guard callVideo else { return }
        camOn.toggle()
        engine?.setCam(camOn)
    }

    private func onInvite(from: String, sdp: String, video: Bool) {
        guard callPhase == .idle else {
            emitDict("call:end", ["to": from])
            return
        }
        callPeer = friendUser(from)
        callVideo = video
        pendingOffer = sdp
        callPhase = .incoming
    }

    private func onAnswer(from: String, sdp: String) {
        guard callPhase == .outgoing, callPeer?.username == from else { return }
        engine?.setAnswer(sdp)
        callPhase = .connected
    }

    private func onIce(from: String, candidate: [String: Any]) {
        guard callPeer?.username == from, let c = Session.iceFrom(candidate) else { return }
        if let e = engine {
            e.addCandidate(c)
        } else {
            pendingIce.append(candidate)
        }
    }

    private func applyPendingIce() {
        for d in pendingIce {
            if let c = Session.iceFrom(d) { engine?.addCandidate(c) }
        }
        pendingIce = []
    }

    private func onRemoteEnd(from: String) {
        guard callPhase != .idle, callPeer?.username == from else { return }
        finishCall(.remote)
    }

    private func sendCandidate(_ c: RTCIceCandidate) {
        guard let peer = callPeer else { return }
        emitDict("call:ice", [
            "to": peer.username,
            "candidate": ["candidate": c.sdp, "sdpMid": c.sdpMid ?? "", "sdpMLineIndex": Int(c.sdpMLineIndex)] as [String: Any]
        ])
    }

    private func connectedNow() {
        if callStart == nil { callStart = Date() }
        callPhase = .connected
    }

    // Итог звонка попадает в переписку как системная запись
    private func finishCall(_ reason: EndReason) {
        guard let peer = callPeer else { return }
        let text: String
        if let start = callStart {
            text = "📞 Звонок · " + Session.mmss(Date().timeIntervalSince(start))
        } else if callPhase == .outgoing {
            text = reason == .remote ? "Звонок отклонён собеседником" : "Звонок отменён"
        } else {
            text = "Пропущенный звонок"
        }
        messages[peer.username, default: []].append(Message(
            id: UUID().uuidString, chatType: "dm", chatId: "", from: Session.callMarker,
            to: nil, text: text, createdAt: Date()))

        engine?.close()
        engine = nil
        localVideo = nil
        remoteVideo = nil
        callPeer = nil
        callStart = nil
        callPhase = .idle
        pendingOffer = nil
        pendingIce = []
        micOn = true
        camOn = true
    }

    nonisolated static func iceFrom(_ d: [String: Any]) -> RTCIceCandidate? {
        guard let sdp = d["candidate"] as? String else { return nil }
        let mid = d["sdpMid"] as? String
        let index = (d["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0
        return RTCIceCandidate(sdp: sdp, sdpMLineIndex: index, sdpMid: mid)
    }

    nonisolated static func mmss(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

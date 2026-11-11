import SwiftUI

// Переход в канал из карточки сервера
struct ChannelRef: Hashable {
    let serverId: String
    let channel: ServerChannel
}

// Картинка из data:-ссылки (аватарки серверов и каналов хранятся в виде data URL)
func dataURLImage(_ s: String?) -> UIImage? {
    guard let s = s, let comma = s.firstIndex(of: ",") else { return nil }
    let b64 = String(s[s.index(after: comma)...])
    guard let data = Data(base64Encoded: b64) else { return nil }
    return UIImage(data: data)
}

let everyoneRoleId = "everyone"

struct PermOption: Identifiable {
    let id: String
    let title: String
}

let rolePermLabels: [PermOption] = [
    PermOption(id: "manageChannels", title: "Управлять каналами"),
    PermOption(id: "manageRoles", title: "Управлять ролями"),
    PermOption(id: "invite", title: "Приглашать по коду"),
    PermOption(id: "kick", title: "Исключать участников"),
]

// MARK: - Список серверов

enum ServersSheet: String, Identifiable {
    case create, join
    var id: String { rawValue }
}

struct ServersView: View {
    @EnvironmentObject var session: Session
    @State var sheet: ServersSheet?

    var body: some View {
        NavigationStack {
            List {
                Section("Мои серверы") {
                    if session.servers.isEmpty {
                        Text("Вы пока не в серверах. Создайте свой или вступите по коду приглашения.")
                            .foregroundStyle(Theme.text2)
                    }
                    ForEach(session.servers) { s in
                        NavigationLink(value: s) {
                            ServerRow(server: s)
                        }
                    }
                }
                Section {
                    Button { sheet = .create } label: {
                        Label("Создать сервер", systemImage: "plus.circle")
                    }
                    Button { sheet = .join } label: {
                        Label("Вступить по коду", systemImage: "ticket")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Серверы")
            .navigationDestination(for: GuildServer.self) { s in
                ServerDetailView(serverId: s.id)
            }
            .navigationDestination(for: ChannelRef.self) { ref in
                ChannelView(ref: ref)
            }
            .refreshable { await session.loadServers() }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .create:
                    PromptSheet(title: "Новый сервер", placeholder: "Название", action: "Создать") { name in
                        await session.createServer(name)
                    }
                case .join:
                    PromptSheet(title: "Вступить по коду", placeholder: "Код приглашения", action: "Вступить") { code in
                        await session.joinServer(code: code.uppercased())
                    }
                }
            }
        }
    }
}

struct ServerRow: View {
    let server: GuildServer

    var body: some View {
        HStack(spacing: 12) {
            if let img = dataURLImage(server.avatar) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Avatar(name: server.name, size: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                Text("\(server.members.count) участников · \(server.channels.count) каналов")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
            }
        }
    }
}

// MARK: - Карточка сервера

enum DetailSheet: Identifiable {
    case newChannel, rename, newRole
    case member(String)

    var id: String {
        switch self {
        case .newChannel: return "newChannel"
        case .rename: return "rename"
        case .newRole: return "newRole"
        case .member(let u): return "member-" + u
        }
    }
}

struct ServerDetailView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) var dismiss
    let serverId: String
    @State var sheet: DetailSheet?
    @State var confirmDelete = false

    private var server: GuildServer? { session.servers.first { $0.id == serverId } }
    private var isOwner: Bool { server?.owner == session.me?.username }

    var body: some View {
        Group {
            if let s = server {
                content(s)
            } else {
                Text("Сервер не найден").foregroundStyle(Theme.text2)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(server?.name ?? "Сервер")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { kind in
            if let s = server { sheetView(kind, s) }
        }
        .confirmationDialog("Удалить сервер вместе с каналами и сообщениями?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task {
                    await session.deleteServer(serverId)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ kind: DetailSheet, _ s: GuildServer) -> some View {
        switch kind {
        case .newChannel:
            PromptSheet(title: "Новый канал", placeholder: "название-канала", action: "Создать") { name in
                await session.createChannel(s.id, name)
            }
        case .rename:
            PromptSheet(title: "Название сервера", placeholder: s.name, action: "Сохранить") { name in
                await session.renameServer(s.id, name)
            }
        case .newRole:
            NewRoleSheet(serverId: s.id)
        case .member(let user):
            MemberRolesSheet(server: s, username: user)
        }
    }

    @ViewBuilder
    private func content(_ s: GuildServer) -> some View {
        List {
            Section("Каналы") {
                ForEach(s.channels) { ch in
                    NavigationLink(value: ChannelRef(serverId: s.id, channel: ch)) {
                        Label(ch.name, systemImage: "number")
                    }
                    .swipeActions {
                        if s.can("manageChannels") {
                            Button(role: .destructive) {
                                Task { await session.deleteChannel(s.id, ch.id) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
                if s.can("manageChannels") {
                    Button { sheet = .newChannel } label: {
                        Label("Новый канал", systemImage: "plus")
                    }
                }
            }

            Section("Участники (\(s.members.count))") {
                ForEach(s.members) { m in
                    Button {
                        if s.can("manageRoles") && !m.owner { sheet = .member(m.username) }
                    } label: {
                        MemberRow(member: m, server: s)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if s.can("kick") && !m.owner && m.username != session.me?.username {
                            Button(role: .destructive) {
                                Task { await session.kick(s.id, user: m.username) }
                            } label: {
                                Label("Исключить", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
            }

            if let code = s.inviteCode {
                Section("Код приглашения") {
                    HStack {
                        Text(code)
                            .font(.system(.title3, design: .monospaced).bold())
                        Spacer()
                        Button("Копировать") {
                            UIPasteboard.general.string = code
                        }
                    }
                    Button("Создать новый код") {
                        Task { await session.regenerateInvite(s.id) }
                    }
                }
            }

            if s.can("manageRoles") {
                Section("Роли") {
                    ForEach(s.roles.filter { $0.id != everyoneRoleId }) { r in
                        HStack {
                            Circle().fill(Color(hex: r.color)).frame(width: 12, height: 12)
                            Text((r.emoji.isEmpty ? "" : r.emoji + " ") + r.name)
                            Spacer()
                            Text(r.perms.count == 0 ? "без прав" : "\(r.perms.count) прав")
                                .font(.caption)
                                .foregroundStyle(Theme.text2)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await session.deleteRole(s.id, r.id) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                    Button { sheet = .newRole } label: {
                        Label("Новая роль", systemImage: "plus")
                    }
                }
            }

            Section {
                if isOwner {
                    Button("Переименовать сервер") { sheet = .rename }
                    Button("Удалить сервер", role: .destructive) { confirmDelete = true }
                } else {
                    Button("Покинуть сервер", role: .destructive) {
                        Task {
                            await session.leaveServer(s.id)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct MemberRow: View {
    let member: ServerMember
    let server: GuildServer

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: member.username, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("@" + member.username)
                    if member.owner { Text("👑") }
                }
                HStack(spacing: 4) {
                    ForEach(server.roles.filter { member.roleIds.contains($0.id) }) { r in
                        Text(r.name)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(hex: r.color).opacity(0.3), in: Capsule())
                    }
                }
            }
            Spacer()
        }
    }
}

// MARK: - Канал

struct ChannelView: View {
    @EnvironmentObject var session: Session
    let ref: ChannelRef
    @State var text = ""

    private var msgs: [Message] { session.channelMessages[ref.channel.id] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            MessageList(messages: msgs, meName: session.me?.username, showAuthor: true)
            Composer(text: $text) { t in
                session.sendChannel(ref.channel.id, text: t)
            }
        }
        .background(AppBackground())
        .navigationTitle("# " + ref.channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.openChannel(ref.channel.id) }
    }
}

// MARK: - Формы

// Одно текстовое поле: название канала, сервера, код приглашения
struct PromptSheet: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let placeholder: String
    let action: String
    @State var value = ""
    let onSubmit: (String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action) {
                        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !v.isEmpty else { return }
                        Task {
                            await onSubmit(v)
                            dismiss()
                        }
                    }
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .background(AppBackground())
        .presentationDetents([.medium])
    }
}

struct NewRoleSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) var dismiss
    let serverId: String
    @State var name = ""
    @State var emoji = ""
    @State var color = "#5b8cff"
    @State var perms: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Роль") {
                    TextField("Название", text: $name)
                    TextField("Эмодзи (необязательно)", text: $emoji)
                    TextField("Цвет #rrggbb", text: $color)
                        .textInputAutocapitalization(.never)
                }
                Section("Права") {
                    ForEach(rolePermLabels) { p in
                        Toggle(p.title, isOn: Binding(
                            get: { perms.contains(p.id) },
                            set: { on in
                                if on { perms.insert(p.id) } else { perms.remove(p.id) }
                            }
                        ))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Новая роль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        let validColor = color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
                        Task {
                            await session.createRole(serverId, name: name.trimmingCharacters(in: .whitespaces),
                                                     color: validColor ? color : "#8a8fa8",
                                                     emoji: emoji, perms: Array(perms))
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .background(AppBackground())
    }
}

// Назначение ролей участнику
struct MemberRolesSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) var dismiss
    let server: GuildServer
    let username: String
    @State var selected: Set<String>

    init(server: GuildServer, username: String) {
        self.server = server
        self.username = username
        let current = server.members.first { $0.username == username }?.roleIds ?? []
        _selected = State(initialValue: Set(current))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("@" + username) {
                    ForEach(server.roles.filter { $0.id != everyoneRoleId }) { r in
                        Toggle(isOn: Binding(
                            get: { selected.contains(r.id) },
                            set: { on in
                                if on { selected.insert(r.id) } else { selected.remove(r.id) }
                            }
                        )) {
                            HStack {
                                Circle().fill(Color(hex: r.color)).frame(width: 10, height: 10)
                                Text(r.name)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Роли участника")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            await session.setMemberRoles(server.id, user: username, roleIds: Array(selected))
                            dismiss()
                        }
                    }
                }
            }
        }
        .background(AppBackground())
    }
}

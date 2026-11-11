import SwiftUI

// MARK: - Корень

struct RootView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var ui: AppUI

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainView().id(prefs.revision)
            } else {
                LoginView().id(prefs.revision)
            }
        }
        .sheet(isPresented: $ui.showSettings) {
            SettingsSheet()
                .environmentObject(session)
                .environmentObject(prefs)
                .environmentObject(ui)
        }
        .preferredColorScheme(.dark)
        .task { await session.restore() }
        .fullScreenCover(isPresented: Binding(
            get: { session.callPhase != .idle },
            set: { _ in }
        )) {
            CallScreen()
        }
        .alert("Ошибка", isPresented: Binding(
            get: { session.error != nil },
            set: { if !$0 { session.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.error ?? "")
        }
    }
}

// MARK: - Вход и регистрация (как .auth в index.html)

struct LoginView: View {
    @EnvironmentObject var session: Session
    @State var registering = true
    @State var name = ""
    @State var nick = ""
    @State var pass = ""
    @State var pass2 = ""
    @State var showPass = false
    @State var err = ""
    @State var busy = false

    var body: some View {
        ZStack {
            Color(hex: "#08080a")
            RadialGradient(colors: [Color.white.opacity(0.06), .clear],
                           center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 600)
            RadialGradient(colors: [Color.white.opacity(0.04), .clear],
                           center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 600)

            ScrollView {
                modal
                    .padding(.horizontal, 20)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
    }

    private var modal: some View {
        VStack(spacing: 0) {
            Text("M")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.grad, in: RoundedRectangle(cornerRadius: 19))
                .shadow(color: Theme.a1.opacity(0.45), radius: 15, y: 12)
                .padding(.bottom, 14)

            Text(registering ? "Создать аккаунт" : "С возвращением")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
            Text(registering ? "Имя, ник и пароль — остальное настроишь потом" : "Войди по нику и паролю")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)

            // .seg
            HStack(spacing: 6) {
                segButton("Регистрация", on: registering) { registering = true; err = "" }
                segButton("Вход", on: !registering) { registering = false; err = "" }
            }
            .padding(5)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 18)

            if registering {
                field("Имя", "Как тебя зовут", $name, max: 24)
                field("Username", "alex_dev", $nick, max: 20)
                passField("Пароль", "минимум 6 символов", $pass)
                strengthBar
                passField("Повтори пароль", "ещё раз", $pass2)
            } else {
                field("Username", "твой username", $nick, max: 20)
                passField("Пароль", "твой пароль", $pass)
            }

            Text(err)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .padding(.bottom, 10)

            Button(action: submit) {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(registering ? "Создать аккаунт" : "Войти")
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !busy))
            .disabled(busy)

            Text("Аккаунт создаётся один раз, дальше входишь по username и паролю")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(
            LinearGradient(colors: [Color(hex: "#1a1a1f"), Color(hex: "#101014")], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 50, y: 40)
    }

    private func segButton(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.white : Theme.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(on ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func field(_ label: String, _ placeholder: String, _ value: Binding<String>, max: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Theme.text3)
            TextField(placeholder, text: value)
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .onChange(of: value.wrappedValue) { v in
                    if v.count > max { value.wrappedValue = String(v.prefix(max)) }
                }
        }
        .padding(.bottom, 14)
    }

    private func passField(_ label: String, _ placeholder: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Theme.text3)
            HStack(spacing: 6) {
                Group {
                    if showPass {
                        TextField(placeholder, text: value)
                    } else {
                        SecureField(placeholder, text: value)
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button(showPass ? "Скрыть" : "Показать") { showPass.toggle() }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        }
        .padding(.bottom, 14)
    }

    private var strengthBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(Theme.grad)
                    .frame(width: g.size.width * min(1, Double(pass.count) / 10))
            }
        }
        .frame(height: 5)
        .padding(.top, -8)
        .padding(.bottom, 14)
    }

    private func submit() {
        err = ""
        let n = nick.trimmingCharacters(in: .whitespaces).lowercased()
        if registering {
            if pass.count < 6 { err = "Пароль не короче 6 символов"; return }
            if pass != pass2 { err = "Пароли не совпадают"; return }
        }
        if n.isEmpty || pass.isEmpty { err = "Заполните поля"; return }
        busy = true
        let display = name.trimmingCharacters(in: .whitespaces)
        Task {
            await session.login(username: n, password: pass, displayName: display, register: registering)
            busy = false
            if let e = session.error {
                err = e
                session.error = nil
            }
        }
    }
}

// MARK: - Основной экран: нижние вкладки как .mtabs в index.html

enum MainTab: Hashable { case channels, chat, friends, profile }

enum ChatTarget: Hashable {
    case dm(User)
    case channel(ChannelRef)
}

struct MainView: View {
    @EnvironmentObject var ui: AppUI

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
            FXLayer()
            Group {
                switch ui.tab {
                case .channels:
                    ChannelsTab(target: $ui.target) { ui.tab = .chat }
                case .chat:
                    ChatTab(target: ui.target)
                case .friends:
                    FriendsTab { t in
                        ui.target = t
                        ui.tab = .chat
                    }
                case .profile:
                    ProfileTab()
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MTabBar(tab: $ui.tab)
        }
    }
}

struct MTabBar: View {
    @Binding var tab: MainTab

    private struct Item: Identifiable {
        let tab: MainTab
        let icon: String
        let title: String
        var id: MainTab { tab }
    }

    private let items: [Item] = [
        Item(tab: .channels, icon: "#", title: "Каналы"),
        Item(tab: .chat, icon: "💬", title: "Чат"),
        Item(tab: .friends, icon: "👥", title: "Друзья"),
        Item(tab: .profile, icon: "👤", title: "Профиль"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { it in
                Button {
                    tab = it.tab
                } label: {
                    VStack(spacing: 2) {
                        Text(it.icon).font(.system(size: 16, weight: .bold))
                        Text(it.title).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(tab == it.tab ? Color.white : Theme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        tab == it.tab ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glass()
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Каналы: серверы-иконки, каналы выбранного сервера, панель пользователя

struct IdString: Identifiable, Hashable {
    let id: String
}

struct ChannelsTab: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var ui: AppUI
    @Binding var target: ChatTarget?
    let onOpen: () -> Void

    @State var selectedId: String?
    @State var sheet: ServersSheet?
    @State var detail: IdString?

    private var current: GuildServer? {
        session.servers.first { $0.id == selectedId } ?? session.servers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // .rail: иконки серверов
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(session.servers) { s in
                        let active = s.id == current?.id
                        Button {
                            selectedId = s.id
                        } label: {
                            Text(String(s.name.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(active ? Color.white : Theme.text2)
                                .frame(width: 54, height: 54)
                                .background(
                                    active ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.white.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: active ? 16 : 18))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { sheet = .create } label: {
                        Text("+")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.a3)
                            .frame(width: 54, height: 54)
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .stroke(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }

            // .ch-head
            HStack {
                Text(current?.name ?? "Серверы")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let s = current {
                    Button { detail = IdString(id: s.id) } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.text2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }

            // .ch-body
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("КАНАЛЫ")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.1)
                            .foregroundStyle(Theme.text3)
                        Spacer()
                        if current?.can("manageChannels") == true {
                            Button { sheet = .newChannel } label: {
                                Text("+").font(.system(size: 16)).foregroundStyle(Theme.text3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                    ForEach(current?.channels ?? []) { ch in
                        let active = isActive(ch)
                        Button {
                            if let s = current {
                                target = .channel(ChannelRef(serverId: s.id, channel: ch))
                                onOpen()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("#")
                                    .font(.system(size: 15, weight: .bold))
                                    .frame(width: 18)
                                    .opacity(0.8)
                                Text(ch.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(active ? Color.white : Theme.text2)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 11)
                            .background(
                                active ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }

            // .me: панель пользователя
            if let me = session.me {
                HStack(spacing: 10) {
                    Avatar(name: me.name, color: me.color, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(me.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(me.status?.isEmpty == false ? me.status ?? "" : "@" + me.username)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture {
                    ui.settingsTab = "profile"
                    ui.showSettings = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glass()
        .sheet(item: $sheet) { kind in
            NavigationStack {
                sheetContent(kind)
            }
        }
        .sheet(item: $detail) { d in
            NavigationStack {
                ServerDetailView(serverId: d.id) { ref in
                    target = .channel(ref)
                    onOpen()
                }
            }
        }
    }

    private func isActive(_ ch: ServerChannel) -> Bool {
        if case .channel(let ref) = target { return ref.channel.id == ch.id }
        return false
    }

    @ViewBuilder
    private func sheetContent(_ kind: ServersSheet) -> some View {
        switch kind {
        case .create:
            PromptSheet(title: "Новый сервер", placeholder: "Название", action: "Создать") { name in
                await session.createServer(name)
            }
        case .join:
            PromptSheet(title: "Вступить по коду", placeholder: "Код приглашения", action: "Вступить") { code in
                await session.joinServer(code: code.uppercased())
            }
        case .newChannel:
            if let s = current {
                PromptSheet(title: "Новый канал", placeholder: "название-канала", action: "Создать") { name in
                    await session.createChannel(s.id, name)
                }
            }
        }
    }
}

enum ServersSheet: String, Identifiable {
    case create, join, newChannel
    var id: String { rawValue }
}

// MARK: - Чат

struct ChatTab: View {
    @EnvironmentObject var session: Session
    let target: ChatTarget?

    var body: some View {
        switch target {
        case .dm(let u):
            DMChat(peer: u)
        case .channel(let ref):
            ChannelChat(ref: ref)
        case nil:
            VStack(spacing: 8) {
                Text("Здесь пока пусто ✨")
                    .foregroundStyle(Theme.text3)
                    .padding(40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass()
        }
    }
}

struct DMChat: View {
    @EnvironmentObject var session: Session
    let peer: User
    @State var text = ""

    var body: some View {
        ChatShell(
            messages: session.messages[peer.username] ?? [],
            placeholder: "Написать: " + peer.name,
            text: $text,
            head: {
                HStack(spacing: 12) {
                    Text(peer.name)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    headButton("phone") { session.startCall(to: peer, video: false) }
                    headButton("video") { session.startCall(to: peer, video: true) }
                }
            },
            onSend: { t in session.send(to: peer.username, text: t) }
        )
        .task { await session.loadMessages(peer.username) }
    }
}

struct ChannelChat: View {
    @EnvironmentObject var session: Session
    let ref: ChannelRef
    @State var text = ""
    @State var detail: IdString?

    var body: some View {
        ChatShell(
            messages: session.channelMessages[ref.channel.id] ?? [],
            placeholder: "Написать в #" + ref.channel.name,
            text: $text,
            head: {
                HStack(spacing: 8) {
                    Text("#")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.a3)
                    Text(ref.channel.name)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    headButton("person.2") { detail = IdString(id: ref.serverId) }
                }
            },
            onSend: { t in session.sendChannel(ref.channel.id, text: t) }
        )
        .task { await session.openChannel(ref.channel.id) }
        .sheet(item: $detail) { d in
            NavigationStack {
                ServerDetailView(serverId: d.id)
            }
        }
    }
}

private func headButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: 17))
            .foregroundStyle(Theme.text2)
            .frame(width: 38, height: 38)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 13))
    }
    .buttonStyle(.plain)
}

// Общая раскладка чата: шапка, лента, поле ввода — как .chat в index.html
struct ChatShell<Head: View>: View {
    @EnvironmentObject var session: Session
    let messages: [Message]
    let placeholder: String
    @Binding var text: String
    let head: Head
    let onSend: (String) -> Void

    init(messages: [Message], placeholder: String, text: Binding<String>,
         @ViewBuilder head: () -> Head, onSend: @escaping (String) -> Void) {
        self.messages = messages
        self.placeholder = placeholder
        self._text = text
        self.head = head()
        self.onSend = onSend
    }

    var body: some View {
        VStack(spacing: 0) {
            head
                .padding(.horizontal, 22)
                .frame(height: 64)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(messages) { m in
                            MsgRow(m: m,
                                   name: session.profiles[m.from]?.name ?? m.from,
                                   meName: session.me?.username)
                                .id(m.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)

            Composer(text: $text, placeholder: placeholder, onSend: onSend)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glass()
    }
}

// Сообщение: аватар, автор, ник, время, текст — как .msg в index.html
struct MsgRow: View {
    let m: Message
    let name: String
    let meName: String?

    var body: some View {
        if m.from == Session.callMarker {
            Text(m.text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Avatar(name: m.from, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text("@" + m.from)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                        Text(m.createdAt, style: .time)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                    }
                    Text(m.text)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// Поле ввода — как .composer-inner в index.html
struct Composer: View {
    @Binding var text: String
    let placeholder: String
    let onSend: (String) -> Void

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Button {} label: {
                Text("+")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)

            Button {} label: {
                Text("☺")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Button {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                text = ""
                onSend(t)
            } label: {
                Text("➤")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.grad, in: RoundedRectangle(cornerRadius: 15))
                    .shadow(color: Theme.a1.opacity(0.45), radius: 11, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .opacity(empty ? 0.35 : 1)
        }
        .padding(.leading, 8)
        .padding(6)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }
}

// MARK: - Друзья (.friends-view)

struct FriendRow: Identifiable {
    let user: User
    let kind: Int   // 0 — друг, 1 — входящая заявка, 2 — исходящая
    var id: String { user.username }
}

struct FriendsTab: View {
    @EnvironmentObject var session: Session
    let onOpen: (ChatTarget) -> Void

    @State var filter = 0
    @State var nick = ""

    private var rows: [FriendRow] {
        switch filter {
        case 1:
            return session.friends.filter { ($0.st ?? "online") == "online" }.map { FriendRow(user: $0, kind: 0) }
        case 2:
            return session.incoming.map { FriendRow(user: $0, kind: 1) }
                + session.outgoing.map { FriendRow(user: $0, kind: 2) }
        default:
            return session.friends.map { FriendRow(user: $0, kind: 0) }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // .fr-top: сегменты
            HStack(spacing: 6) {
                filterButton("Все", 0)
                filterButton("В сети", 1)
                filterButton("Заявки", 2)
            }
            .padding(5)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))

            // .fr-add
            HStack(spacing: 8) {
                TextField("Добавить по username, например dev_xeno", text: $nick)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                Button("Добавить") {
                    let n = nick.trimmingCharacters(in: .whitespaces).lowercased()
                    nick = ""
                    Task { await session.requestFriend(n) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 120)
                .disabled(nick.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // .fr-list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { r in
                        friendRow(r.user, kind: r.kind)
                    }
                    if rows.isEmpty {
                        Text("Здесь пока пусто ✨")
                            .foregroundStyle(Theme.text3)
                            .padding(.vertical, 40)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glass()
    }

    private func filterButton(_ title: String, _ idx: Int) -> some View {
        Button {
            filter = idx
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filter == idx ? Color.white : Theme.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(filter == idx ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func friendRow(_ u: User, kind: Int) -> some View {
        HStack(spacing: 12) {
            Avatar(name: u.name, color: u.color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(u.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("@" + u.username)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
            switch kind {
            case 1:
                iconAction("checkmark") { Task { await session.accept(u.username) } }
            case 2:
                Text("ожидает")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            default:
                iconAction("bubble.left") { onOpen(.dm(u)) }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }

    private func iconAction(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text2)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Профиль

struct ProfileTab: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var ui: AppUI
    @State var editing = false

    var body: some View {
        ScrollView {
            if let me = session.me {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Theme.grad)
                        .frame(height: 150)
                    VStack(alignment: .leading, spacing: 10) {
                        Avatar(name: me.name, color: me.color, size: 92)
                            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.p.bg, lineWidth: 5))
                            .padding(.top, -46)
                        Text(me.name)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text("@" + me.username)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text3)
                        if let bio = me.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.text2)
                                .lineSpacing(3)
                        }
                        Button("Редактировать профиль") {
                            ui.settingsTab = "profile"
                            ui.showSettings = true
                        }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 10)
                        Button("Выйти") { session.logout() }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
                .glass()
                .sheet(isPresented: $editing) {
                    NavigationStack {
                        ProfileEditSheet(user: me)
                    }
                }
            }
        }
    }
}

struct ProfileEditSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) var dismiss
    let user: User
    @State var displayName: String
    @State var bio: String
    @State var status: String
    @State var color: String

    init(user: User) {
        self.user = user
        _displayName = State(initialValue: user.displayName ?? "")
        _bio = State(initialValue: user.bio ?? "")
        _status = State(initialValue: user.status ?? "")
        _color = State(initialValue: user.color ?? "#5b8cff")
    }

    var body: some View {
        Form {
            Section("Профиль") {
                TextField("Имя", text: $displayName)
                TextField("О себе", text: $bio, axis: .vertical)
                TextField("Статус", text: $status)
                TextField("Цвет #rrggbb", text: $color)
                    .textInputAutocapitalization(.never)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") {
                    let validColor = color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
                    Task {
                        await session.updateProfile(
                            displayName: displayName.trimmingCharacters(in: .whitespaces),
                            bio: String(bio.prefix(190)),
                            status: String(status.prefix(64)),
                            color: validColor ? color : nil)
                        dismiss()
                    }
                }
            }
        }
    }
}

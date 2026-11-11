import SwiftUI

// MARK: - Тема (цвета из www/index.html, тема «ocean»)

enum Theme {
    static let bg = Color(hex: "#060a1c")
    static let glass = Color(red: 20 / 255, green: 30 / 255, blue: 68 / 255).opacity(0.55)
    static let a1 = Color(hex: "#5b8cff")
    static let a2 = Color(hex: "#8a6bff")
    static let a3 = Color(hex: "#36d1ff")
    static let text2 = Color(hex: "#a3b1de")
    static let text3 = Color(hex: "#66739f")
    static let danger = Color(hex: "#ff5d6c")
    static var grad: LinearGradient {
        LinearGradient(colors: [a1, a2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }
}

// Фон приложения: тёмный с мягкими цветными пятнами, как в HTML
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            Circle().fill(Theme.a1.opacity(0.3)).frame(width: 360).blur(radius: 90).offset(x: -150, y: -300)
            Circle().fill(Theme.a2.opacity(0.28)).frame(width: 320).blur(radius: 90).offset(x: 160, y: 320)
        }
        .ignoresSafeArea()
    }
}

// Общий стиль карточек и кнопок
struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.grad, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Корень: вход или основное приложение

struct RootView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
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

// MARK: - Вход и регистрация

struct LoginView: View {
    @EnvironmentObject var session: Session
    @State var registering = false
    @State var username = ""
    @State var password = ""
    @State var displayName = ""
    @State var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Messenger 2026")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.grad)
                    .padding(.top, 60)

                Picker("Режим", selection: $registering) {
                    Text("Вход").tag(false)
                    Text("Регистрация").tag(true)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    field("Юзернейм", text: $username)
                    if registering { field("Имя (необязательно)", text: $displayName) }
                    SecureField("Пароль", text: $password)
                        .padding(14)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
                }

                Button(action: submit) {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text(registering ? "Создать аккаунт" : "Войти")
                    }
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(14)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
    }

    private func submit() {
        busy = true
        let name = username.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            await session.login(username: name, password: password,
                                displayName: displayName.trimmingCharacters(in: .whitespaces),
                                register: registering)
            busy = false
        }
    }
}

// MARK: - Основной экран

struct MainView: View {
    var body: some View {
        TabView {
            FriendsView()
                .tabItem { Label("Друзья", systemImage: "person.2") }
            ServersView()
                .tabItem { Label("Серверы", systemImage: "square.grid.2x2") }
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
        .tint(Theme.a3)
    }
}

// MARK: - Друзья и заявки

struct FriendsView: View {
    @EnvironmentObject var session: Session
    @State var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Добавить в друзья") {
                    HStack {
                        TextField("Юзернейм", text: $newName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Отправить") {
                            let n = newName.trimmingCharacters(in: .whitespaces).lowercased()
                            newName = ""
                            Task { await session.requestFriend(n) }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !session.incoming.isEmpty {
                    Section("Входящие заявки") {
                        ForEach(session.incoming) { u in
                            HStack {
                                UserLabel(user: u)
                                Spacer()
                                Button("Принять") {
                                    Task { await session.accept(u.username) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.a1)
                            }
                        }
                    }
                }

                if !session.outgoing.isEmpty {
                    Section("Исходящие заявки") {
                        ForEach(session.outgoing) { u in
                            UserLabel(user: u).foregroundStyle(Theme.text2)
                        }
                    }
                }

                Section("Друзья") {
                    if session.friends.isEmpty {
                        Text("Пока никого. Добавьте друга по юзернейму.")
                            .foregroundStyle(Theme.text2)
                    }
                    ForEach(session.friends) { u in
                        NavigationLink(value: u) {
                            UserLabel(user: u)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Друзья")
            .navigationDestination(for: User.self) { u in
                ChatView(peer: u)
            }
            .refreshable {
                await session.loadFriends()
            }
        }
    }
}

// MARK: - Личные сообщения

struct ChatView: View {
    @EnvironmentObject var session: Session
    let peer: User
    @State var text = ""

    private var msgs: [Message] { session.messages[peer.username] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            MessageList(messages: msgs, meName: session.me?.username, showAuthor: false)
            Composer(text: $text) { t in
                session.send(to: peer.username, text: t)
            }
        }
        .background(AppBackground())
        .navigationTitle(peer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { session.startCall(to: peer, video: false) } label: {
                    Image(systemName: "phone")
                }
                Button { session.startCall(to: peer, video: true) } label: {
                    Image(systemName: "video")
                }
            }
        }
        .task { await session.loadMessages(peer.username) }
    }
}

// Список сообщений с автопрокруткой вниз (используется для ЛС и каналов)
struct MessageList: View {
    let messages: [Message]
    let meName: String?
    let showAuthor: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { m in
                        Bubble(message: m, mine: m.from == meName, showAuthor: showAuthor)
                            .id(m.id)
                    }
                }
                .padding(12)
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
    }
}

struct Composer: View {
    @Binding var text: String
    let onSend: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Сообщение", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1)))

            Button {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                text = ""
                onSend(t)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.grad)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(Theme.glass)
    }
}

struct Bubble: View {
    let message: Message
    let mine: Bool
    let showAuthor: Bool

    var body: some View {
        if message.from == Session.callMarker {
            Text(message.text)
                .font(.footnote)
                .foregroundStyle(Theme.text2)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
        } else {
            HStack {
                if mine { Spacer(minLength: 48) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    if showAuthor && !mine {
                        Text("@" + message.from)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.a3)
                    }
                    Text(message.text)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(mine ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Theme.glass))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(Theme.text3)
                }
                if !mine { Spacer(minLength: 48) }
            }
        }
    }
}

// MARK: - Профиль

struct ProfileView: View {
    @EnvironmentObject var session: Session
    @State var editing = false

    var body: some View {
        NavigationStack {
            List {
                if let me = session.me {
                    Section {
                        UserLabel(user: me)
                        if !me.bio.isNilOrEmpty { Text(me.bio ?? "").foregroundStyle(Theme.text2) }
                    }
                    Section {
                        Button("Редактировать профиль") { editing = true }
                    }
                }
                Section {
                    Button("Выйти", role: .destructive) {
                        session.logout()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Профиль")
            .sheet(isPresented: $editing) {
                if let me = session.me {
                    ProfileEditSheet(user: me)
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
        NavigationStack {
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
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
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
        .background(AppBackground())
    }
}

// MARK: - Общие элементы

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

struct UserLabel: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: user.name, color: user.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                Text("@" + user.username)
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
            }
        }
    }
}

struct Avatar: View {
    let name: String
    var color: String?
    var size: CGFloat = 40

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.map { Color(hex: $0) } ?? Theme.a1, in: Circle())
    }
}

import SwiftUI

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
        .task { await session.restore() }
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
    @State private var registering = false
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Режим", selection: $registering) {
                        Text("Вход").tag(false)
                        Text("Регистрация").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    TextField("Юзернейм", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if registering {
                        TextField("Имя (необязательно)", text: $displayName)
                    }
                    SecureField("Пароль", text: $password)
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if busy {
                                ProgressView()
                            } else {
                                Text(registering ? "Создать аккаунт" : "Войти").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Messenger 2026")
        }
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
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
    }
}

// MARK: - Друзья и заявки

struct FriendsView: View {
    @EnvironmentObject var session: Session
    @State private var newName = ""

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
                            }
                        }
                    }
                }

                if !session.outgoing.isEmpty {
                    Section("Исходящие заявки") {
                        ForEach(session.outgoing) { u in
                            UserLabel(user: u).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Друзья") {
                    if session.friends.isEmpty {
                        Text("Пока никого. Добавьте друга по юзернейму.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.friends) { u in
                        NavigationLink(value: u) {
                            UserLabel(user: u)
                        }
                    }
                }
            }
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
    @State private var text = ""

    private var msgs: [Message] { session.messages[peer.username] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(msgs) { m in
                            Bubble(message: m, mine: m.from == session.me?.username)
                                .id(m.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: msgs.count) { _ in
                    if let last = msgs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = msgs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            composer
        }
        .navigationTitle(peer.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.loadMessages(peer.username) }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Сообщение", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.bar)
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        session.send(to: peer.username, text: t)
        text = ""
    }
}

struct Bubble: View {
    let message: Message
    let mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(mine ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !mine { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Профиль

struct ProfileView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        NavigationStack {
            List {
                if let me = session.me {
                    Section {
                        UserLabel(user: me)
                    }
                }
                Section {
                    Button("Выйти", role: .destructive) {
                        session.logout()
                    }
                }
            }
            .navigationTitle("Профиль")
        }
    }
}

// MARK: - Общие элементы

struct UserLabel: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            Text(String(user.name.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                Text("@" + user.username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

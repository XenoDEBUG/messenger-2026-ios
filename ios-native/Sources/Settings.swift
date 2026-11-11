import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Общие элементы настроек (.switch-row, .seg, .field, .toggle из index.html)

struct HTMLToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.white.opacity(0.15)))
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SwitchRow: View {
    let title: String
    var sub: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                if let sub = sub {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                }
            }
            Spacer()
            HTMLToggle(isOn: $isOn)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

// .seg: переключатель из нескольких вариантов
struct SegControl: View {
    let options: [Opt]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { o in
                Button {
                    selection = o.id
                } label: {
                    Text(o.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == o.id ? Color.white : Theme.text2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 6)
                        .background(
                            selection == o.id ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct Opt: Identifiable, Hashable {
    let id: String
    let label: String
}

func opt(_ id: String, _ label: String) -> Opt { Opt(id: id, label: label) }

struct StatusOpt: Identifiable {
    let id: String
    let label: String
    let color: String
    let desc: String
}

struct TabOpt: Identifiable {
    let id: String
    let name: String
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(Theme.text3)
    }
}

struct PaneTitle: View {
    let title: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.text)
            if let sub = sub {
                Text(sub)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text3)
            }
        }
    }
}

struct InputBox: View {
    let placeholder: String
    @Binding var text: String
    var max: Int = 200

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 16))
            .foregroundStyle(Theme.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            .onChange(of: text) { v in
                if v.count > max { text = String(v.prefix(max)) }
            }
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            Slider(value: $value, in: range)
                .tint(Theme.a3)
        }
    }
}

struct DropBox: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        }
        .buttonStyle(.plain)
    }
}

// Цвет SwiftUI → hex #rrggbb
func hexString(_ c: Color) -> String {
    let ui = UIColor(c)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
}

// MARK: - Окно настроек (.modal.settings)

struct SettingsSheet: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var ui: AppUI
    @EnvironmentObject var prefs: Prefs
    @Environment(\.dismiss) var dismiss

    private let tabs: [TabOpt] = [
        TabOpt(id: "profile", name: "Профиль"),
        TabOpt(id: "look", name: "Оформление"),
        TabOpt(id: "anim", name: "Анимации"),
        TabOpt(id: "notif", name: "Уведомления"),
        TabOpt(id: "data", name: "Данные"),
        TabOpt(id: "layout", name: "Раскладка"),
        TabOpt(id: "fx", name: "Фон и эффекты"),
        TabOpt(id: "account", name: "Аккаунт"),
    ]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("Настройки")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.a3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                // .s-nav: на телефоне — строка вкладок
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { t in
                            Button {
                                ui.settingsTab = t.id
                            } label: {
                                Text(t.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(ui.settingsTab == t.id ? Color.white : Theme.text2)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        ui.settingsTab == t.id ? AnyShapeStyle(Theme.grad) : AnyShapeStyle(Color.clear),
                                        in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }

                ScrollView {
                    pane
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var pane: some View {
        switch ui.settingsTab {
        case "look": LookPane()
        case "anim": AnimPane()
        case "notif": NotifPane()
        case "data": DataPane()
        case "layout": LayoutPane()
        case "fx": FxPane()
        case "account": AccountPane()
        default: ProfilePane()
        }
    }
}

// MARK: - Профиль (.s-pane[data-pane=profile])

struct ProfilePane: View {
    @EnvironmentObject var session: Session
    @State var name = ""
    @State var bio = ""
    @State var color = Color(hex: "#5b8cff")
    @State var st = "online"
    @State var ytLink = ""
    @State var tgLink = ""
    @State var ttLink = ""
    @State var pickedAvatar: PhotosPickerItem?
    @State var pickedBanner: PhotosPickerItem?

    private let statuses: [StatusOpt] = [
        StatusOpt(id: "online", label: "В сети", color: "#3ddc97", desc: "Все видят тебя и пишут"),
        StatusOpt(id: "idle", label: "Отошёл", color: "#ffb547", desc: "Скоро вернусь"),
        StatusOpt(id: "dnd", label: "Не беспокоить", color: "#ff5c7a", desc: "Без уведомлений и звонков"),
        StatusOpt(id: "invis", label: "Невидимка", color: "#7d86a8", desc: "Выглядишь оффлайн для всех"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneTitle(title: "Профиль")

            // .profile-banner
            bannerView
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            PhotosPicker(selection: $pickedBanner, matching: .images) {
                Text("Загрузить картинку для баннера")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            }

            // .profile-top: аватарка и имя
            HStack(spacing: 18) {
                PhotosPicker(selection: $pickedAvatar, matching: .images) {
                    ZStack {
                        if let me = session.me {
                            Avatar(name: me.name, color: me.color, size: 88)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.me?.name ?? "")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Text("@" + (session.me?.username ?? ""))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(16)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Имя")
                    InputBox(placeholder: "Имя", text: $name, max: 24)
                }
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Username")
                    Text("@" + (session.me?.username ?? ""))
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "О себе")
                InputBox(placeholder: "Пара слов о себе", text: $bio, max: 190)
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Статус")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(statuses) { s in
                        Button {
                            st = s.id
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Color(hex: s.color)).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.label).font(.system(size: 14, weight: .bold))
                                    Text(s.desc).font(.system(size: 11)).foregroundStyle(Theme.text3)
                                }
                                Spacer()
                                if st == s.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: s.color))
                                }
                            }
                            .foregroundStyle(Theme.text)
                            .padding(10)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(st == s.id ? Color(hex: s.color) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                FieldLabel(text: "Цвет профиля")
                Spacer()
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
            }
            Text("Свой цвет профиля — его видят в списке участников")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Соцсети")
                InputBox(placeholder: "youtube.com/@ник", text: $ytLink, max: 120)
                InputBox(placeholder: "t.me/ник", text: $tgLink, max: 120)
                InputBox(placeholder: "tiktok.com/@ник", text: $ttLink, max: 120)
            }

            Button("Сохранить") {
                Task {
                    await session.patchProfile([
                        "displayName": name.trimmingCharacters(in: .whitespaces),
                        "bio": bio,
                        "color": hexString(color),
                        "st": st,
                        "links": ["yt": ytLink, "tg": tgLink, "tt": ttLink],
                    ])
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
        }
        .onAppear(perform: load)
        .onChange(of: pickedAvatar) { item in
            Task {
                guard let item = item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data),
                      let url = imageDataURL(img, maxSide: 256) else { return }
                await session.patchProfile(["avatar": url])
            }
        }
        .onChange(of: pickedBanner) { item in
            Task {
                guard let item = item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data),
                      let url = imageDataURL(img, maxSide: 1200) else { return }
                await session.patchProfile(["banner": url])
            }
        }
    }

    private func load() {
        guard let me = session.me else { return }
        name = me.displayName ?? ""
        bio = me.bio ?? ""
        color = Color(hex: me.color ?? "#5b8cff")
        st = me.st ?? "online"
    }

    @ViewBuilder
    private var bannerView: some View {
        if let img = dataURLImage(session.me?.banner) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Theme.grad
        }
    }
}

// MARK: - Оформление (.s-pane[data-pane=look])

struct LookPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "Тема")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Palettes.list) { t in
                    Button {
                        prefs.d.theme = t.id
                        prefs.d.mono = false
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .bottomLeading) {
                                Color(hex: t.bg)
                                HStack(spacing: 4) {
                                    ForEach(t.swatches, id: \.self) { c in
                                        Circle().fill(Color(hex: c)).frame(width: 12, height: 12)
                                    }
                                }
                                .padding(8)
                            }
                            .frame(height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            Text(t.name)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.text)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(prefs.d.theme == t.id && !prefs.d.mono ? Theme.a3 : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Плотность")
                SegControl(options: [opt("cozy", "Просторно"), opt("comfy", "Обычно"), opt("compact", "Компактно")],
                           selection: $prefs.d.density)
            }

            SliderRow(label: "Скругления: \(Int(prefs.d.radius))px", value: $prefs.d.radius, range: 6...32)

            SwitchRow(title: "Фоновые пятна", sub: "Плавающие цветные облака", isOn: $prefs.d.blobs)
            SwitchRow(title: "Монохром всего приложения",
                      sub: "Весь интерфейс в чёрно-белых тонах",
                      isOn: $prefs.d.mono)
        }
    }
}

// MARK: - Анимации

struct AnimPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "Анимации")
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Уровень")
                SegControl(options: [opt("off", "Выкл"), opt("normal", "Обычные"), opt("max", "Максимум")],
                           selection: $prefs.d.anim)
            }
            SwitchRow(title: "Частицы при отправке", sub: "Искры из кнопки отправки", isOn: $prefs.d.particles)
            SwitchRow(title: "Конфетти при регистрации", sub: "Салют на старте", isOn: $prefs.d.confetti)
            SwitchRow(title: "Всплывающие уведомления", sub: "Тосты в правом нижнем углу", isOn: $prefs.d.toasts)
        }
    }
}

// MARK: - Уведомления

struct NotifPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "Уведомления")
            SwitchRow(title: "Упоминания", sub: "Когда упоминают тебя", isOn: $prefs.d.n1)
            SwitchRow(title: "Звуки", sub: "Сигнал при новом сообщении", isOn: $prefs.d.n2)
            SwitchRow(title: "Индикатор «печатает»", sub: "Показывать, когда ты печатаешь", isOn: $prefs.d.n3)
        }
    }
}

// MARK: - Данные: экспорт и импорт настроек

struct DataPane: View {
    @EnvironmentObject var prefs: Prefs
    @State var importing = false
    @State var message = ""

    private var exportText: String {
        guard let data = try? JSONEncoder().encode(prefs.d) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "Данные", sub: "Сохрани настройки в файл, чтобы перенести их или восстановить позже.")

            HStack(spacing: 10) {
                ShareLink(item: exportText) {
                    Text("Экспорт настроек")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 11)
                        .padding(.horizontal, 20)
                        .background(Theme.grad, in: RoundedRectangle(cornerRadius: 14))
                }
                Button("Импорт…") { importing = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 20)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               let v = try? JSONDecoder().decode(PrefsData.self, from: data) {
                prefs.d = v
                message = "Настройки импортированы"
            } else {
                message = "Не удалось прочитать файл"
            }
        }
    }
}

// MARK: - Раскладка: на телефоне панели фиксированы

struct LayoutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "Раскладка",
                      sub: "На телефоне панели стоят в одном порядке: перетаскивать их можно в версии для ПК.")
        }
    }
}

// MARK: - Фон и эффекты

struct FxPane: View {
    @EnvironmentObject var prefs: Prefs
    @State var pickedBg: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "Фон и эффекты")

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Спецэффект")
                SegControl(options: [opt("none", "✕ Нет"), opt("rain", "🌧 Дождь"), opt("snow", "❄ Снег"), opt("rays", "☀ Лучи")],
                           selection: $prefs.d.fx)
            }

            SliderRow(label: "Количество", value: $prefs.d.fxAmt, range: 10...100)

            HStack {
                FieldLabel(text: "Цвет эффекта")
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: prefs.d.fxColor) },
                    set: { prefs.d.fxColor = hexString($0) }), supportsOpacity: false)
                    .labelsHidden()
            }

            PhotosPicker(selection: $pickedBg, matching: .images) {
                Text("Перетащи картинку фона или нажми, чтобы выбрать")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            }

            SliderRow(label: "Видимость фото", value: $prefs.d.imgOp, range: 0...100)

            HStack {
                FieldLabel(text: "Цвет фона")
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: prefs.d.bgTint ?? "#060a1c") },
                    set: { prefs.d.bgTint = hexString($0) }), supportsOpacity: false)
                    .labelsHidden()
                Button("Сбросить") { prefs.d.bgTint = nil }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text2)
            }

            Button("Убрать фото фона") { prefs.d.bgImage = nil }
                .font(.system(size: 14))
                .foregroundStyle(Theme.text2)
        }
        .onChange(of: pickedBg) { item in
            Task {
                guard let item = item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data),
                      let jpeg = imageJPEG(img, maxSide: 1600) else { return }
                prefs.d.bgImage = jpeg
            }
        }
    }
}

// MARK: - Аккаунт

struct AccountPane: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var ui: AppUI

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "Аккаунт", sub: "Выход вернёт на экран входа.")
            Button("Выйти из аккаунта") {
                ui.showSettings = false
                session.logout()
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.danger)
            .padding(.vertical, 11)
            .padding(.horizontal, 20)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

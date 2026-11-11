import SwiftUI
import UIKit

// Все настройки из index.html (localStorage на сайте, UserDefaults в приложении)
struct PrefsData: Codable, Equatable {
    var theme = "ocean"
    var mono = false
    var radius: Double = 22
    var density = "comfy"           // cozy / comfy / compact
    var blobs = true
    var anim = "normal"             // off / normal / max
    var particles = true
    var confetti = true
    var toasts = true
    var n1 = true                   // упоминания
    var n2 = false                  // звуки
    var n3 = true                   // индикатор «печатает»
    var fx = "none"                 // none / rain / snow / rays
    var fxAmt: Double = 60
    var fxColor = "#ffffff"
    var imgOp: Double = 40
    var bgTint: String? = nil       // цвет фона, если задан
    var bgImage: Data? = nil        // фото фона
}

// Палитры тем из index.html
struct ThemeOption: Identifiable {
    let id: String
    let name: String
    let swatches: [String]
    let bg: String
}

enum Palettes {
    static let ocean = Theme.ocean
    static let sunset = Palette(
        bg: Color(hex: "#1a0712"), glass: rgba(70, 22, 46, 0.5), glass2: rgba(40, 12, 28, 0.65),
        a1: Color(hex: "#ff7a59"), a2: Color(hex: "#ff3d7f"), a3: Color(hex: "#ffc23d"),
        text: Color(hex: "#fff1ea"), text2: Color(hex: "#f0b8c8"), text3: Color(hex: "#9c6a7c"),
        line: rgba(255, 160, 130, 0.16), blobA: rgba(255, 122, 89, 0.35), blobB: rgba(255, 61, 127, 0.3))
    static let neon = Palette(
        bg: Color(hex: "#05030d"), glass: rgba(30, 14, 60, 0.55), glass2: rgba(12, 6, 30, 0.65),
        a1: Color(hex: "#39ff9e"), a2: Color(hex: "#00d4ff"), a3: Color(hex: "#ff3dff"),
        text: Color(hex: "#eafff6"), text2: Color(hex: "#9ff5d0"), text3: Color(hex: "#4f7a6c"),
        line: rgba(57, 255, 158, 0.16), blobA: rgba(57, 255, 158, 0.25), blobB: rgba(255, 61, 255, 0.25))
    static let aurora = Palette(
        bg: Color(hex: "#03131a"), glass: rgba(10, 50, 60, 0.5), glass2: rgba(5, 25, 32, 0.6),
        a1: Color(hex: "#2ee6c5"), a2: Color(hex: "#7b8cff"), a3: Color(hex: "#ffe66d"),
        text: Color(hex: "#e6fffa"), text2: Color(hex: "#9fe3d8"), text3: Color(hex: "#557f7a"),
        line: rgba(46, 230, 197, 0.14), blobA: rgba(46, 230, 197, 0.3), blobB: rgba(155, 107, 255, 0.3))
    static let candy = Palette(
        bg: Color(hex: "#fff3fb"), glass: rgba(255, 255, 255, 0.6), glass2: rgba(255, 255, 255, 0.8),
        a1: Color(hex: "#ff4fa3"), a2: Color(hex: "#7c5cff"), a3: Color(hex: "#ffb703"),
        text: Color(hex: "#3a1d4d"), text2: Color(hex: "#7a4f8f"), text3: Color(hex: "#b08fc2"),
        line: rgba(255, 79, 163, 0.18), blobA: rgba(255, 79, 163, 0.3), blobB: rgba(255, 210, 63, 0.35))
    static let mono = Palette(
        bg: Color(hex: "#08080a"), glass: rgba(30, 30, 36, 0.5), glass2: rgba(16, 16, 20, 0.65),
        a1: Color(hex: "#f2f2f5"), a2: Color(hex: "#9a9aa6"), a3: Color(hex: "#ffffff"),
        text: Color(hex: "#f2f2f5"), text2: Color(hex: "#a4a4b0"), text3: Color(hex: "#5d5d68"),
        line: rgba(255, 255, 255, 0.08), blobA: rgba(255, 255, 255, 0.08), blobB: rgba(140, 140, 153, 0.1))

    static let byId: [String: Palette] = [
        "ocean": ocean, "sunset": sunset, "neon": neon, "aurora": aurora, "candy": candy, "mono": mono,
    ]

    // Названия и три цвета-превью из THEMES в index.html
    static let list: [ThemeOption] = [
        ThemeOption(id: "ocean", name: "Ocean", swatches: ["#5b8cff", "#8a6bff", "#36d1ff"], bg: "#0b1230"),
        ThemeOption(id: "sunset", name: "Sunset", swatches: ["#ffb13d", "#ff3d7f", "#c23dff"], bg: "#2a0c1c"),
        ThemeOption(id: "neon", name: "Neon", swatches: ["#39ff9e", "#00d4ff", "#ff3dff"], bg: "#0c0820"),
        ThemeOption(id: "aurora", name: "Aurora", swatches: ["#2ee6c5", "#3aa8ff", "#9b6bff"], bg: "#062430"),
        ThemeOption(id: "candy", name: "Candy", swatches: ["#ff4fa3", "#ff8a4c", "#ffd23f"], bg: "#ffe6f5"),
        ThemeOption(id: "mono", name: "Mono", swatches: ["#f2f2f5", "#9a9aa6", "#5d5d68"], bg: "#111114"),
    ]
}

// Единая точка: изменения настроек сразу применяются к теме, фону и эффектам
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()

    @Published var d: PrefsData {
        didSet {
            save()
            apply()
            revision += 1
        }
    }
    @Published var revision = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: "prefs"),
           let v = try? JSONDecoder().decode(PrefsData.self, from: data) {
            d = v
        } else {
            d = PrefsData()
        }
        apply()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(d) {
            UserDefaults.standard.set(data, forKey: "prefs")
        }
    }

    func apply() {
        var pal = Palettes.byId[d.theme] ?? Palettes.ocean
        if d.mono { pal = Palettes.mono }
        Theme.p = pal
        Theme.radius = CGFloat(d.radius)
        Theme.blobsOn = d.blobs
        Theme.bgTint = d.bgTint.map { Color(hex: $0) }
        Theme.bgImage = d.bgImage.flatMap { UIImage(data: $0) }
        Theme.imgOpacity = d.imgOp / 100
        Theme.padding = d.density == "cozy" ? 14 : (d.density == "compact" ? 4 : 10)
    }
}

// Состояние навигации, которое должно пережить смену темы
@MainActor
final class AppUI: ObservableObject {
    static let shared = AppUI()
    @Published var showSettings = false
    @Published var settingsTab = "profile"
    @Published var tab: MainTab = .chat
    @Published var target: ChatTarget?
}

// Слой спецэффектов: дождь, снег, лучи — как .fx в index.html
struct FXLayer: View {
    var body: some View {
        let kind = Prefs.shared.d.fx
        let amt = Int(Prefs.shared.d.fxAmt)
        let color = Color(hex: Prefs.shared.d.fxColor)
        if kind != "none" {
            TimelineView(.animation) { ctx in
                Canvas { gc, size in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    switch kind {
                    case "rain":
                        for i in 0..<amt {
                            let seed = Double(i) * 37.13
                            let x = (seed.truncatingRemainder(dividingBy: 1) * size.width + Double(i) * 13).truncatingRemainder(dividingBy: size.width)
                            let speed = 500 + (seed.truncatingRemainder(dividingBy: 300))
                            let y = (t * speed + seed * 97).truncatingRemainder(dividingBy: size.height + 40) - 20
                            var p = Path()
                            p.move(to: CGPoint(x: x, y: y))
                            p.addLine(to: CGPoint(x: x - 6, y: y + 16))
                            gc.stroke(p, with: .color(color.opacity(0.5)), lineWidth: 1.2)
                        }
                    case "snow":
                        for i in 0..<amt {
                            let seed = Double(i) * 53.7
                            let x = (seed * 17).truncatingRemainder(dividingBy: size.width) + sin(t + seed) * 20
                            let y = (t * 40 + seed * 31).truncatingRemainder(dividingBy: size.height + 20) - 10
                            let r = 1.5 + (seed.truncatingRemainder(dividingBy: 3))
                            gc.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                    with: .color(color.opacity(0.7)))
                        }
                    default: // rays
                        let c = CGPoint(x: size.width * 0.5, y: -size.height * 0.1)
                        for i in 0..<max(4, amt / 10) {
                            let a = Double(i) * (2 * .pi / Double(max(4, amt / 10))) + t * 0.1
                            var p = Path()
                            p.move(to: c)
                            p.addLine(to: CGPoint(x: c.x + cos(a - 0.05) * size.height * 2, y: c.y + sin(a - 0.05) * size.height * 2))
                            p.addLine(to: CGPoint(x: c.x + cos(a + 0.05) * size.height * 2, y: c.y + sin(a + 0.05) * size.height * 2))
                            p.closeSubpath()
                            gc.fill(p, with: .color(color.opacity(0.05)))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

// Картинка в JPEG-строку data:image для сервера (лимит 600 КБ)
func imageDataURL(_ img: UIImage, maxSide: CGFloat) -> String? {
    let scale = min(1, maxSide / max(img.size.width, img.size.height))
    let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    let small = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    for q in [0.8, 0.6, 0.45, 0.3] as [CGFloat] {
        if let d = small.jpegData(compressionQuality: q) {
            let s = "data:image/jpeg;base64," + d.base64EncodedString()
            if s.count <= 600000 { return s }
        }
    }
    return nil
}

// Картинка фона в JPEG для локального хранения
func imageJPEG(_ img: UIImage, maxSide: CGFloat) -> Data? {
    let scale = min(1, maxSide / max(img.size.width, img.size.height))
    let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
    let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    return small.jpegData(compressionQuality: 0.7)
}

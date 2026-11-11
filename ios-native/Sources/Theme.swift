import SwiftUI
import UIKit

// Палитра из www/index.html (тема «ocean» — по умолчанию)
struct Palette {
    let bg: Color
    let glass: Color
    let glass2: Color
    let a1: Color
    let a2: Color
    let a3: Color
    let text: Color
    let text2: Color
    let text3: Color
    let line: Color
    let blobA: Color
    let blobB: Color
}

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255).opacity(a)
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

enum Theme {
    static let ocean = Palette(
        bg: Color(hex: "#060a1c"),
        glass: rgba(20, 30, 68, 0.55),
        glass2: rgba(10, 16, 40, 0.62),
        a1: Color(hex: "#5b8cff"),
        a2: Color(hex: "#8a6bff"),
        a3: Color(hex: "#36d1ff"),
        text: Color(hex: "#e8eeff"),
        text2: Color(hex: "#a3b1de"),
        text3: Color(hex: "#66739f"),
        line: rgba(120, 150, 255, 0.14),
        blobA: rgba(91, 140, 255, 0.35),
        blobB: rgba(138, 107, 255, 0.30))

    static var p = ocean
    static var radius: CGFloat = 22         // --r из настроек «Скругления»
    static var blobsOn = true               // «Фоновые пятна»
    static var bgTint: Color? = nil         // «Цвет фона»
    static var bgImage: UIImage? = nil      // «Свой фон»
    static var imgOpacity: Double = 0.4     // «Видимость фото»
    static var padding: CGFloat = 10        // плотность: --pad

    static var bg: Color { p.bg }
    static var glass: Color { p.glass }
    static var glass2: Color { p.glass2 }
    static var a1: Color { p.a1 }
    static var a2: Color { p.a2 }
    static var a3: Color { p.a3 }
    static var text: Color { p.text }
    static var text2: Color { p.text2 }
    static var text3: Color { p.text3 }
    static var line: Color { p.line }

    static let danger = Color(hex: "#ff5c7a")

    // --grad: linear-gradient(135deg, a1, a2)
    static var grad: LinearGradient {
        LinearGradient(colors: [p.a1, p.a2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Аватарки без своего градиента: GRADS[name.length % 6] из index.html
    static let grads: [LinearGradient] = [
        grad2("#5b8cff", "#8a6bff"),
        grad2("#ff6b9d", "#c44dff"),
        grad2("#ffb347", "#ff6b6b"),
        grad2("#3ddc97", "#2aa3ff"),
        grad2("#36d1ff", "#3ddc97"),
        grad2("#ffe66d", "#ff8a4c"),
    ]

    static func gradFor(_ name: String) -> LinearGradient {
        grads[name.count % grads.count]
    }

    private static func grad2(_ a: String, _ b: String) -> LinearGradient {
        LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// Фон: тёмная база, фото, и три размытых пятна, как .bg / .blob в index.html
struct AppBackground: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let m = max(w, h)
            ZStack {
                Theme.bgTint ?? Theme.p.bg
                if let img = Theme.bgImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .opacity(Theme.imgOpacity)
                        .clipped()
                }
                if Theme.blobsOn {
                    // .b1: 60vmax, top -20vmax, left -15vmax
                    Circle().fill(Theme.p.blobA)
                        .frame(width: m * 0.6, height: m * 0.6)
                        .blur(radius: 90)
                        .position(x: m * 0.15, y: m * 0.1)
                    // .b2: 60vmax, bottom -25vmax, right -15vmax
                    Circle().fill(Theme.p.blobB)
                        .frame(width: m * 0.6, height: m * 0.6)
                        .blur(radius: 90)
                        .position(x: w - m * 0.15, y: h - m * 0.05)
                    // .b3: 40vmax, top 30%, left 40%, opacity .25
                    Circle().fill(Theme.p.a3.opacity(0.25))
                        .frame(width: m * 0.4, height: m * 0.4)
                        .blur(radius: 90)
                        .position(x: w * 0.4 + m * 0.2, y: h * 0.3 + m * 0.2)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

// Стекло: .glass из index.html
struct GlassBox: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(colors: [Theme.p.glass, Theme.p.glass2], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: radius))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.p.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func glass(_ radius: CGFloat? = nil) -> some View {
        modifier(GlassBox(radius: radius ?? Theme.radius))
    }
}

// Кнопка .btn-primary
struct PrimaryButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Theme.grad, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: Theme.a1.opacity(0.45), radius: 11, y: 8)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// Аватар .av: 38px, скругление 13px, градиент по имени
struct Avatar: View {
    let name: String
    var color: String?
    var size: CGFloat = 38

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.37, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                color.map { AnyShapeStyle(Color(hex: $0)) } ?? AnyShapeStyle(Theme.gradFor(name)),
                in: RoundedRectangle(cornerRadius: size * 0.34))
    }
}

import SwiftUI
import WebRTC

// Экран звонка: входящий, исходящий и активный. Показывается поверх всего приложения.
struct CallScreen: View {
    @EnvironmentObject var session: Session

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if session.callVideo, let remote = session.remoteVideo {
                VideoView(track: remote).ignoresSafeArea()
            } else {
                AppBackground()
            }

            VStack(spacing: 20) {
                header
                Spacer()
                if session.remoteVideo == nil, let peer = session.callPeer {
                    Avatar(name: peer.name, color: peer.color, size: 120)
                }
                Spacer()
                if session.callVideo, session.callPhase == .connected, let local = session.localVideo {
                    HStack {
                        Spacer()
                        VideoView(track: local)
                            .frame(width: 110, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                controls
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(session.callPeer?.name ?? "")
                .font(.title2.bold())
                .foregroundStyle(.white)
            statusLine
                .foregroundStyle(Theme.text2)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch session.callPhase {
        case .incoming:
            Text(session.callVideo ? "Входящий видеозвонок" : "Входящий звонок")
        case .outgoing:
            Text("Вызов…")
        case .connected:
            if let start = session.callStart {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    Text(Session.mmss(ctx.date.timeIntervalSince(start)))
                        .monospacedDigit()
                }
            } else {
                Text("Соединение…")
            }
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        if session.callPhase == .incoming {
            HStack(spacing: 48) {
                roundButton("phone.down.fill", color: Theme.danger) { session.declineCall() }
                roundButton(session.callVideo ? "video.fill" : "phone.fill", color: .green) { session.acceptCall() }
            }
        } else {
            HStack(spacing: 22) {
                roundButton(session.micOn ? "mic.fill" : "mic.slash.fill",
                            color: Color.white.opacity(0.2)) { session.toggleMic() }
                if session.callVideo {
                    roundButton(session.camOn ? "video.fill" : "video.slash.fill",
                                color: Color.white.opacity(0.2)) { session.toggleCam() }
                }
                roundButton("phone.down.fill", color: Theme.danger) { session.hangUp() }
            }
        }
    }

    private func roundButton(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(color, in: Circle())
        }
    }
}

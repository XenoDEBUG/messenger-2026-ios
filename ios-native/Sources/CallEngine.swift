import Foundation
import SwiftUI
import AVFoundation
import CoreMedia
import WebRTC

// Одно WebRTC-соединение 1 на 1. Сигналы (SDP и ICE) передаёт Session через сокет,
// сервер только пересылает их. Голос и видео идут напрямую между устройствами.
final class CallEngine: NSObject {
    let video: Bool

    var onCandidate: ((RTCIceCandidate) -> Void)?
    var onConnected: (() -> Void)?
    var onFailed: (() -> Void)?
    var onRemoteVideo: ((RTCVideoTrack?) -> Void)?

    private(set) var localVideo: RTCVideoTrack?

    private let factory = RTCPeerConnectionFactory()
    private var pc: RTCPeerConnection?
    private var audioTrack: RTCAudioTrack?
    private var videoTrack: RTCVideoTrack?
    private var capturer: RTCCameraVideoCapturer?
    private var remoteDescSet = false
    private var pendingCandidates: [RTCIceCandidate] = []

    init(video: Bool) {
        self.video = video
        super.init()
    }

    func setup() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? AVAudioSession.sharedInstance().setActive(true)

        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        let audioSource = factory.audioSource(with: constraints)
        let audio = factory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack = audio
        pc?.add(audio, streamIds: ["stream0"])

        if video { addVideo() }
    }

    private func addVideo() {
        let source = factory.videoSource()
        let track = factory.videoTrack(with: source, trackId: "video0")
        videoTrack = track
        localVideo = track
        pc?.add(track, streamIds: ["stream0"])

        let cap = RTCCameraVideoCapturer(delegate: source)
        capturer = cap
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == .front }) ?? devices.first else { return }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.first(where: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width >= 640 })
                ?? formats.last else { return }
        let fps = min(30, Int(format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30))
        cap.startCapture(with: device, format: format, fps: fps)
    }

    // Звонящий: создаём предложение
    func makeOffer(completion: @escaping (String) -> Void) {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
            optionalConstraints: nil)
        pc?.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else { self?.onFailed?(); return }
            self.pc?.setLocalDescription(sdp) { err in
                if err == nil { completion(sdp.sdp) } else { self.onFailed?() }
            }
        }
    }

    // Принимающий: применяем предложение и создаём ответ
    func acceptOffer(_ sdp: String, completion: @escaping (String) -> Void) {
        let remote = RTCSessionDescription(type: .offer, sdp: sdp)
        pc?.setRemoteDescription(remote) { [weak self] err in
            guard let self = self, err == nil else { self?.onFailed?(); return }
            self.remoteDescSet = true
            self.flushCandidates()
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            self.pc?.answer(for: constraints) { answer, e in
                guard let answer = answer, e == nil else { self.onFailed?(); return }
                self.pc?.setLocalDescription(answer) { err2 in
                    if err2 == nil { completion(answer.sdp) } else { self.onFailed?() }
                }
            }
        }
    }

    func setAnswer(_ sdp: String) {
        let remote = RTCSessionDescription(type: .answer, sdp: sdp)
        pc?.setRemoteDescription(remote) { [weak self] err in
            guard let self = self, err == nil else { return }
            self.remoteDescSet = true
            self.flushCandidates()
        }
    }

    func addCandidate(_ c: RTCIceCandidate) {
        if remoteDescSet {
            pc?.add(c) { _ in }
        } else {
            pendingCandidates.append(c)
        }
    }

    private func flushCandidates() {
        for c in pendingCandidates { pc?.add(c) { _ in } }
        pendingCandidates = []
    }

    func setMic(_ on: Bool) { audioTrack?.isEnabled = on }
    func setCam(_ on: Bool) { videoTrack?.isEnabled = on }

    func close() {
        capturer?.stopCapture()
        capturer = nil
        pc?.close()
        pc = nil
        localVideo = nil
        videoTrack = nil
        audioTrack = nil
    }
}

extension CallEngine: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let v = stream.videoTracks.first { onRemoteVideo?(v) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver,
                        streams: [RTCMediaStream]) {
        if let v = rtpReceiver.track as? RTCVideoTrack { onRemoteVideo?(v) }
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed: onConnected?()
        case .failed: onFailed?()
        default: break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onCandidate?(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// Отображение видеодорожки WebRTC в SwiftUI
struct VideoView: UIViewRepresentable {
    let track: RTCVideoTrack?

    final class Coordinator {
        var track: RTCVideoTrack?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        if context.coordinator.track !== track {
            context.coordinator.track?.remove(view)
            track?.add(view)
            context.coordinator.track = track
        }
    }
}

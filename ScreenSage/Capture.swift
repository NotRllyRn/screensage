#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
import CoreImage
import UIKit

@MainActor
final class Capture: NSObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
    var onFrame: ((Frame) -> Void)?
    var onState: ((String) -> Void)?
    var onEnd: (() -> Void)?
    private var stream: SCStream?
    private var generation = 0
    private var accepting = false
    private var lastFrame = Date.distantPast
    private let context = CIContext()

    override init() { super.init(); SCContentSharingPicker.shared.add(self) }
    func start() {
        guard !accepting else { return }
        Diagnostics.shared.record("capture.picker_requested")
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else { Diagnostics.shared.record("capture.unavailable"); onState?("Screen sharing is unavailable on this device."); onEnd?(); return }
        generation += 1; accepting = true; lastFrame = .distantPast
        var config = SCContentSharingPickerConfiguration(); config.showsMicrophoneControl = false; config.showsCameraControl = false
        picker.defaultConfiguration = config; picker.isActive = true
        onState?("Waiting for system screen-sharing approval…"); picker.present()
    }
    func stop() async {
        generation += 1; accepting = false
        let old = stream; stream = nil
        SCContentSharingPicker.shared.isActive = false
        do { try await old?.stopCapture(); Diagnostics.shared.record("capture.stopped") }
        catch { Diagnostics.shared.error("capture.stop_error", error) }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            guard self.accepting, self.stream == nil else { return }
            let token = self.generation
            let config = SCStreamConfiguration()
            let created = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try created.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                self.stream = created
                try await created.startCapture()
                guard self.accepting, self.generation == token else { try? await created.stopCapture(); return }
                Diagnostics.shared.record("capture.started")
                self.onState?("Sharing full screen · waiting for frames")
            } catch {
                Diagnostics.shared.error("capture.start_error", error)
                guard self.generation == token else { return }
                await self.stop(); self.onState?("Capture could not start. Check system sharing permission."); self.onEnd?()
            }
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) { Task { @MainActor in
        guard self.accepting, self.stream == nil else { return }
        Diagnostics.shared.record("capture.picker_cancelled")
        await self.stop(); self.onState?("Screen sharing cancelled"); self.onEnd?()
    } }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) { Task { @MainActor in
        Diagnostics.shared.error("capture.picker_error", error)
        await self.stop(); self.onState?("System screen-sharing picker failed"); self.onEnd?()
    } }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) { Task { @MainActor in
        guard self.stream === stream else { return }
        Diagnostics.shared.error("capture.system_stop", error)
        await self.stop(); self.onState?("Screen sharing ended by the system"); self.onEnd?()
    } }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        MainActor.assumeIsolated {
            guard accepting, self.stream === stream, type == .screen, sampleBuffer.isValid,
                  Date().timeIntervalSince(lastFrame) >= 10,
                  let buffer = sampleBuffer.imageBuffer else { return }
            let metadata = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first
            if let status = metadata?[.status] as? Int, status != SCFrameStatus.complete.rawValue { return }
            let orientation = (metadata?[.videoOrientation] as? NSNumber)?.int32Value ?? 1
            let source = CIImage(cvPixelBuffer: buffer).oriented(forExifOrientation: orientation)
            let scale = min(1, 1200 / max(source.extent.width, source.extent.height))
            let resized = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(resized, from: resized.extent) else { return }
            lastFrame = Date(); onFrame?(Frame(image: UIImage(cgImage: cg), date: lastFrame))
        }
    }
}

#else
import Foundation

// Apple does not ship ScreenCaptureKit in this iOS simulator SDK.
@MainActor
final class Capture {
    var onFrame: ((Frame) -> Void)?
    var onState: ((String) -> Void)?
    var onEnd: (() -> Void)?
    func start() { Diagnostics.shared.record("capture.simulator_unavailable"); onState?("Full-screen capture requires a physical iOS 27 device; unavailable in this simulator."); onEnd?() }
    func stop() async {}
}
#endif

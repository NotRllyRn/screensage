import UIKit

struct Frame {
    let image: UIImage
    let date: Date
}

struct FrameWindow {
    private(set) var frames: [Frame] = []
    private(set) var accepted = 0
    mutating func append(_ frame: Frame) -> Bool {
        if let last = frames.last, frame.date.timeIntervalSince(last.date) < 10 { return false }
        frames.append(frame)
        if frames.count > 6 { frames.removeFirst() }
        accepted += 1
        return true
    }
    mutating func clear() { frames = []; accepted = 0 }
}

enum ContactSheet {
    static func render(_ frames: [Frame]) -> Data? {
        guard !frames.isEmpty else { return nil }
        let cell = CGSize(width: 720, height: 1000)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1440, height: 3000), format: format)
        let image = renderer.image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1440, height: 3000))
            for (index, frame) in frames.prefix(6).enumerated() {
                let origin = CGPoint(x: CGFloat(index % 2) * cell.width, y: CGFloat(index / 2) * cell.height)
                let label = "\(index + 1) · \(frame.date.formatted(.iso8601))"
                (label as NSString).draw(at: CGPoint(x: origin.x + 12, y: origin.y + 10), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 23, weight: .medium), .foregroundColor: UIColor.white])
                let area = CGRect(x: origin.x + 8, y: origin.y + 48, width: 704, height: 944)
                let scale = min(area.width / frame.image.size.width, area.height / frame.image.size.height)
                let size = CGSize(width: frame.image.size.width * scale, height: frame.image.size.height * scale)
                frame.image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}

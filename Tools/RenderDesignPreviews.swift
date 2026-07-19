import AppKit
import SwiftUI
import WidgetKit

@main
@MainActor
struct RenderDesignPreviews {
    private static let outputDirectory = URL(fileURLWithPath: "/tmp/CodexLimitsDesignPreviews", isDirectory: true)

    static func main() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try render(name: "small", family: .systemSmall, size: CGSize(width: 158, height: 158))
        try render(name: "medium", family: .systemMedium, size: CGSize(width: 338, height: 158))
        try render(name: "large", family: .systemLarge, size: CGSize(width: 338, height: 354))
    }

    private static func render(name: String, family: WidgetFamily, size: CGSize) throws {
        let entry = LimitEntry(date: .now, dashboard: previewDashboard)
        let content = ZStack {
            CodexAuroraBackground()
            CodexLimitsWidgetView(entry: entry, previewFamily: family)
                .padding(16)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw PreviewError.renderFailed(name)
        }
        try png.write(
            to: outputDirectory.appendingPathComponent("\(name).png"),
            options: Data.WritingOptions.atomic
        )
    }

    private static var previewDashboard: CodexDashboardSnapshot {
        CodexDashboardSnapshot(
            updatedAt: .now.addingTimeInterval(-11),
            accounts: [
                account(id: "default", name: "Default", remaining: 46, resetHours: 136),
                account(id: "mastersoft", name: "Mastersoft", remaining: 0, resetHours: 130)
            ]
        )
    }

    private static func account(id: String, name: String, remaining: Int, resetHours: Int) -> CodexAccountSnapshot {
        CodexAccountSnapshot(
            id: id,
            name: name,
            email: "\(id)@example.com",
            limits: CodexLimitSnapshot(
                fetchedAt: .now.addingTimeInterval(-11),
                plan: "Plus",
                windows: [
                    CodexLimitWindow(
                        id: "\(id)-weekly",
                        title: "Weekly",
                        usedPercent: 100 - remaining,
                        resetsAt: .now.addingTimeInterval(TimeInterval(resetHours * 3_600)),
                        durationMinutes: 10_080
                    )
                ],
                creditBalance: nil,
                resetCredits: [
                    CodexResetCredit(id: "\(id)-1", title: "Full reset", expiresAt: .now.addingTimeInterval(7 * 86_400)),
                    CodexResetCredit(id: "\(id)-2", title: "Full reset", expiresAt: .now.addingTimeInterval(11 * 86_400)),
                    CodexResetCredit(id: "\(id)-3", title: "Full reset", expiresAt: .now.addingTimeInterval(23 * 86_400))
                ]
            ),
            errorMessage: nil
        )
    }
}

private enum PreviewError: LocalizedError {
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case let .renderFailed(name): "Could not render \(name) widget preview"
        }
    }
}

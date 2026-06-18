import AppKit
import PasswardsCore
import UniformTypeIdentifiers

/// Renders the Emergency Kit PDF: sign-in details, Secret Key, and a blank
/// line for the account password — modeled on 1Password's kit.
enum EmergencyKitPDF {
    static func save(email: String, secretKey: SecretKey, presentingWindow: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Passwards Emergency Kit.pdf"
        panel.title = "Save Emergency Kit"

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try render(email: email, secretKey: secretKey).write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let presentingWindow {
            panel.beginSheetModal(for: presentingWindow, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    static func render(email: String, secretKey: SecretKey) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        context.beginPDFPage(nil)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        // Header band in brand blue
        let headerRect = CGRect(x: 0, y: 712, width: 612, height: 80)
        NSColor(srgbRed: 0x05 / 255, green: 0x72 / 255, blue: 0xEC / 255, alpha: 1).setFill()
        context.fill(headerRect)

        func draw(_ string: String, at point: CGPoint, font: NSFont, color: NSColor = .black) {
            (string as NSString).draw(
                at: point,
                withAttributes: [.font: font, .foregroundColor: color]
            )
        }

        draw("Passwards Emergency Kit", at: CGPoint(x: 48, y: 740), font: .boldSystemFont(ofSize: 24), color: .white)
        draw("Keep this document somewhere safe — anyone with it and your account password can access your data.",
             at: CGPoint(x: 48, y: 690), font: .systemFont(ofSize: 10), color: .darkGray)

        var y: CGFloat = 630
        func field(_ label: String, _ value: String, monospaced: Bool = false) {
            draw(label.uppercased(), at: CGPoint(x: 48, y: y), font: .boldSystemFont(ofSize: 9), color: .gray)
            let font = monospaced
                ? NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
                : NSFont.systemFont(ofSize: 14)
            draw(value, at: CGPoint(x: 48, y: y - 20), font: font)
            y -= 64
        }

        field("Created", Date().formatted(date: .long, time: .shortened))
        field("Email address", email)
        field("Secret Key", secretKey.formatted, monospaced: true)

        draw("ACCOUNT PASSWORD", at: CGPoint(x: 48, y: y), font: .boldSystemFont(ofSize: 9), color: .gray)
        NSColor.gray.setStroke()
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 48, y: y - 24))
        context.addLine(to: CGPoint(x: 400, y: y - 24))
        context.strokePath()
        draw("Write your account password here, or leave blank and memorize it.",
             at: CGPoint(x: 48, y: y - 40), font: .systemFont(ofSize: 9), color: .gray)

        draw("Your Secret Key is stored only on this Mac's Keychain and in this document. " +
             "Without it, your data cannot be decrypted on a new device.",
             at: CGPoint(x: 48, y: 80), font: .systemFont(ofSize: 9), color: .darkGray)

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

import SwiftUI
import TwoPasswordCore

@main
struct TwoPasswordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("2Password", id: "main") {
            ContentPlaceholderView()
        }
    }
}

struct ContentPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
            Text("2Password")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
        }
        .frame(minWidth: 600, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0x05 / 255.0, green: 0x72 / 255.0, blue: 0xEC / 255.0))
    }
}

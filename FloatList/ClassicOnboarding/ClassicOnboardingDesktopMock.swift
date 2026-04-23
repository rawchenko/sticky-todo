import SwiftUI

/// macOS desktop mockup: wallpaper + menubar, with a caller-supplied slot on
/// the top-right where the docked FloatList content lives. An optional
/// `overlay` builder sits above the docked content (e.g. the scripted cursor).
struct ClassicOnboardingDesktopMock<Content: View, Overlay: View>: View {
    let dockedContent: Content
    let overlay: Overlay
    let onSizeChange: (CGSize) -> Void

    init(
        onSizeChange: @escaping (CGSize) -> Void = { _ in },
        @ViewBuilder dockedContent: () -> Content,
        @ViewBuilder overlay: () -> Overlay = { EmptyView() }
    ) {
        self.dockedContent = dockedContent()
        self.overlay = overlay()
        self.onSizeChange = onSizeChange
    }

    @State private var menuBarDate: String = Self.currentMenuBarDate()
    @State private var menuBarTime: String = Self.currentMenuBarTime()

    private let menuBarHeight: CGFloat = 28

    var body: some View {
        ZStack(alignment: .topTrailing) {
            wallpaper

            dockedContent
                .padding(.top, menuBarHeight + 18)
                .padding(.trailing, 18)

            overlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)

            menuBar
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onSizeChange(proxy.size) }
                    .onChange(of: proxy.size) { _, newValue in onSizeChange(newValue) }
            }
        )
    }

    private var wallpaper: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.14, blue: 0.20),
                Color(red: 0.18, green: 0.22, blue: 0.30),
                Color(red: 0.28, green: 0.34, blue: 0.44)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var menuBar: some View {
        HStack(spacing: 11) {
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            Image(systemName: "magnifyingglass")
            Text(menuBarDate)
                .padding(.leading, 6)
            Text(menuBarTime)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 13)
        .frame(height: menuBarHeight)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
        )
        .overlay(
            Divider().opacity(0.35),
            alignment: .bottom
        )
    }

    private static func currentMenuBarDate() -> String {
        Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private static func currentMenuBarTime() -> String {
        Date().formatted(date: .omitted, time: .shortened)
    }
}

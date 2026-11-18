import SwiftUI

/// State shown in the floating window.
@MainActor
final class OverlayModel: ObservableObject {
    @Published var text = ""
    @Published var status = "Listening"
    @Published var isWorking = false
    @Published var level: Float = 0

    /// Height of the full text, reported by the view so the window can size itself.
    @Published var textHeight: CGFloat = 0
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    LevelMeter(level: model.level).opacity(model.isWorking ? 0 : 1)
                    ProgressView().controlSize(.small).opacity(model.isWorking ? 1 : 0)
                }
                .frame(width: 26, height: 18)
                Text(model.status.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            transcript
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 480, alignment: .leading)
        .modifier(GlassBackground(shape: shape))
    }
}

extension OverlayView {
    static let maxTextHeight: CGFloat = 132      // about six lines, then it scrolls

    /// The full transcript in a scroll view that always sticks to the newest words.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.text.isEmpty ? "Speak now…" : model.text)
                        .font(.system(size: 17))
                        .foregroundStyle(model.text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: TextHeightKey.self, value: geo.size.height)
                })
            }
            .scrollIndicators(.visible)
            .frame(height: min(max(model.textHeight, 22), Self.maxTextHeight))
            .mask(                                   // soft fade where older text scrolls out of view
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black, location: model.textHeight > Self.maxTextHeight ? 0.14 : 0),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .onPreferenceChange(TextHeightKey.self) { h in
                DispatchQueue.main.async { model.textHeight = h }
            }
            .onChange(of: model.text) { _ in scrollToEnd(proxy) }
            .onChange(of: model.textHeight) { _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Liquid Glass on macOS 26+, a standard blur material before that.
private struct GlassBackground: ViewModifier {
    let shape: RoundedRectangle
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}

/// Five bars that dance with the microphone level.
private struct LevelMeter: View {
    let level: Float
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    let wobble = 0.55 + 0.45 * abs(sin(Double(i) * 1.7 + t * 7))
                    let h = 4 + CGFloat(level) * CGFloat(wobble) * 14
                    Capsule().fill(Color.red).frame(width: 3, height: h)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

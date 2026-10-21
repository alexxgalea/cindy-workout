import SwiftUI
import UIKit

/// One of a sheet's two buttons. Only the secondary uses `tint`: the primary is the one filled
/// control. A button closes the sheet after its action runs, unless `keepingOpen` says not to:
/// true leaves the sheet up, for a button that refused what it was asked to keep or that only
/// steps the sheet on to another panel.
struct SheetButton {
    let title: String
    var tint: Color
    let action: () -> Void
    private(set) var keepsOpen: () -> Bool = { false }

    init(title: String, tint: Color = Palette.label, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.action = action
    }

    /// The same button, asked after its action has run whether to leave the sheet up.
    func keepingOpen(_ when: @escaping () -> Bool) -> SheetButton {
        var copy = self
        copy.keepsOpen = when
        return copy
    }
}

private struct CloseCindySheetKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Closes the Cindy sheet this view is in. Set by the presenter; a panel's buttons call it.
    var closeCindySheet: () -> Void {
        get { self[CloseCindySheetKey.self] }
        set { self[CloseCindySheetKey.self] = newValue }
    }
}

extension View {
    /// The app's own bottom sheet, `CindySheet.kt`, in place of the system's alerts and sheets.
    ///
    /// A system alert is the one surface that cannot be brought into the design: its title, its
    /// buttons and its corners come from the system and ignore everything in `CindyType`. This is
    /// square glass flush with the bottom edge over a dimmed screen, so it can sit over the live
    /// camera as Android's does.
    ///
    /// Attach it at the root of a screen. The screen beneath leaves the accessibility tree and stops
    /// taking touches while the sheet is up. `onDismiss` runs once however the sheet closes, after
    /// any button's action: a tap on the dim, a swipe down and the accessibility escape gesture
    /// close it without running either button, as Android's back gesture does.
    func cindySheet<Content: View>(isPresented: Binding<Bool>, title: String, subtitle: String? = nil,
                                   primary: SheetButton, secondary: SheetButton? = nil,
                                   secondaryDismisses: Bool = true, onDismiss: @escaping () -> Void = {},
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(CindySheetPresenter(
            item: Binding(get: { isPresented.wrappedValue ? Presented() : nil },
                          set: { if $0 == nil { isPresented.wrappedValue = false } }),
            onDismiss: onDismiss,
            panel: { _ in
                CindyPanel(title: title, subtitle: subtitle, primary: primary, secondary: secondary,
                           secondaryDismisses: secondaryDismisses, content: content)
            }))
    }

    /// A sheet that is only words: a question.
    func cindySheet(isPresented: Binding<Bool>, title: String, subtitle: String? = nil,
                    primary: SheetButton, secondary: SheetButton? = nil,
                    secondaryDismisses: Bool = true, onDismiss: @escaping () -> Void = {}) -> some View {
        cindySheet(isPresented: isPresented, title: title, subtitle: subtitle, primary: primary,
                   secondary: secondary, secondaryDismisses: secondaryDismisses, onDismiss: onDismiss,
                   content: { EmptyView() })
    }

    /// A sheet that is a view of its own: `panel` builds the `CindyPanel` for whichever item is up,
    /// and a different item replaces the one showing. The panel's buttons close it through
    /// `closeCindySheet`, and so does a tap on the dim, a swipe down or the escape gesture, after
    /// which `onDismiss` runs once. Whatever the panel started stops in its own `onDisappear`.
    func cindySheet<Item: Identifiable, Panel: View>(item: Binding<Item?>, onDismiss: @escaping () -> Void = {},
                                                    @ViewBuilder panel: @escaping (Item) -> Panel) -> some View {
        modifier(CindySheetPresenter(item: item, onDismiss: onDismiss, panel: panel))
    }
}

/// What the `isPresented` form presents: the one sheet there is.
private struct Presented: Identifiable { let id = 0 }

private struct SheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Android's `decelerate_quint`, 300 ms.
private let sheetCurve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)

/// The dim, the slide, the drag, the escape gesture, and the isolation of what is beneath: everything
/// a sheet is except what it says.
private struct CindySheetPresenter<Item: Identifiable, Panel: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: () -> Void
    @ViewBuilder let panel: (Item) -> Panel

    @State private var drag: CGFloat = 0

    func body(content base: Content) -> some View {
        base
            .accessibilityHidden(item != nil)
            .allowsHitTesting(item == nil)
            .overlay {
                ZStack(alignment: .bottom) {
                    if let current = item {
                        Palette.scrim
                            .ignoresSafeArea(.container)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        panel(current)
                            .id(current.id)
                            .environment(\.closeCindySheet, { close() })
                            .offset(y: drag)
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { drag = max(0, $0.translation.height) }
                                    .onEnded { value in
                                        if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                                            close()
                                        } else {
                                            withAnimation(sheetCurve) { drag = 0 }
                                        }
                                    })
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("cindySheet")
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape) { close() }
                            .transition(.move(edge: .bottom))
                    }
                }
                .animation(sheetCurve, value: item?.id)
            }
            .onChange(of: item?.id) { was, now in
                if now != nil { drag = 0 }
                if was != nil && now == nil { onDismiss() }
            }
    }

    private func close() { item = nil }
}

/// A sheet's own view: the handle, the title, the words and content that scroll inside 60% of the
/// height, and the two buttons. A sheet is a view whose body is one of these, presented by item.
struct CindyPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    let primary: SheetButton
    let secondary: SheetButton?
    let secondaryDismisses: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.closeCindySheet) private var close
    @State private var bodyHeight: CGFloat = 0

    init(title: String, subtitle: String? = nil, primary: SheetButton, secondary: SheetButton? = nil,
         secondaryDismisses: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.primary = primary
        self.secondary = secondary
        self.secondaryDismisses = secondaryDismisses
        self.content = content
    }

    /// A long sheet must not push its own buttons off the screen: its words and content scroll
    /// inside 60% of the height.
    private static var bodyCap: CGFloat { UIScreen.main.bounds.height * 0.6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(argb: 0x33FFFFFF))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            Text(title).cindy(.title2)
                .accessibilityAddTraits(.isHeader)
            scrollingBody
            buttons.padding(.top, 18)
        }
        .padding(.top, 12).padding(.horizontal, 20).padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The glass runs on under the home indicator, while the words stay above it, and the
        // keyboard still lifts everything: only the container safe area is ignored.
        .background(
            LinearGradient(stops: [.init(color: Palette.specular, location: 0),
                                   .init(color: Palette.sheetMid, location: 0.003),
                                   .init(color: Palette.sheetEnd, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(.container, edges: .bottom))
    }

    /// The subtitle and the content, 18 below the title's line, capped at 60% of the height.
    @ViewBuilder private var scrollingBody: some View {
        if subtitle != nil || Content.self != EmptyView.self {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let subtitle {
                        Text(subtitle).cindy(.callout).padding(.top, 5)
                    }
                    content().padding(.top, Content.self == EmptyView.self ? 0 : 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
                })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(bodyHeight, 1), Self.bodyCap))
            .onPreferenceChange(SheetContentHeightKey.self) { bodyHeight = $0 }
        }
    }

    /// The secondary first, the primary after it and taking the rest of the width. When the type is
    /// large enough that they no longer fit side by side they stack, the filled one on top.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                if let secondary { secondaryButton(secondary) }
                primaryButton.frame(maxWidth: .infinity)
            }
            VStack(spacing: 10) {
                primaryButton
                if let secondary { secondaryButton(secondary) }
            }
        }
    }

    private var primaryButton: some View {
        Button(primary.title) {
            primary.action()
            if !primary.keepsOpen() { close() }
        }
        .buttonStyle(CindyPrimaryButtonStyle())
        .accessibilityIdentifier("sheetPrimary")
    }

    private func secondaryButton(_ button: SheetButton) -> some View {
        Button(button.title) {
            button.action()
            if secondaryDismisses && !button.keepsOpen() { close() }
        }
        .buttonStyle(CindyGlassButtonStyle(tint: button.tint))
        .accessibilityIdentifier("sheetSecondary")
    }
}

/// A switch in a sheet (`CindySheet.kt`'s `toggle`): a glass row at least 52 high.
struct SheetToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label).cindy(.callout, colour: Palette.label)
        }
        .toggleStyle(SwitchToggleStyle(tint: Palette.stateOk))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 52)
        .glassCard()
        .padding(.top, 20)
    }
}

/// A slider in a sheet (`CindySheet.kt`'s `slider`): its label and percentage on one line, and the
/// slider below. `onSettled` fires when the drag ends, not on every step of it.
struct SheetSlider: View {
    let label: String
    @Binding var value: Double
    let onSettled: (Double) -> Void

    init(_ label: String, value: Binding<Double>, onSettled: @escaping (Double) -> Void = { _ in }) {
        self.label = label
        _value = value
        self.onSettled = onSettled
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(label).cindy(.callout, colour: Palette.label)
                Spacer()
                Text("\(Int((value * 100).rounded()))%").cindy(.headline)
            }
            Slider(value: $value, in: 0...1) { editing in
                if !editing { onSettled(value) }
            }
            .tint(Palette.label)
            .accessibilityLabel(label)
        }
        .padding(14)
        .glassCard()
        .padding(.top, 14)
    }
}

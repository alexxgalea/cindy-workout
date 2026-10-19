import SwiftUI
import UIKit

/// One of a sheet's two buttons. Only the secondary uses `tint`: the primary is the one filled
/// control.
struct SheetButton {
    let title: String
    var tint: Color = Palette.label
    let action: () -> Void
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
        modifier(CindySheetModifier(isPresented: isPresented, title: title, subtitle: subtitle,
                                    primary: primary, secondary: secondary,
                                    secondaryDismisses: secondaryDismisses, onDismiss: onDismiss,
                                    content: content))
    }

    /// A sheet that is only words: a question.
    func cindySheet(isPresented: Binding<Bool>, title: String, subtitle: String? = nil,
                    primary: SheetButton, secondary: SheetButton? = nil,
                    secondaryDismisses: Bool = true, onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(CindySheetModifier(isPresented: isPresented, title: title, subtitle: subtitle,
                                    primary: primary, secondary: secondary,
                                    secondaryDismisses: secondaryDismisses, onDismiss: onDismiss,
                                    content: { EmptyView() }))
    }
}

private struct SheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct CindySheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let subtitle: String?
    let primary: SheetButton
    let secondary: SheetButton?
    let secondaryDismisses: Bool
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> SheetContent

    @State private var drag: CGFloat = 0
    @State private var bodyHeight: CGFloat = 0

    /// Android's `decelerate_quint`, 300 ms.
    private static var curve: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.3) }
    /// A long sheet must not push its own buttons off the screen: its words and content scroll
    /// inside 60% of the height.
    private static var bodyCap: CGFloat { UIScreen.main.bounds.height * 0.6 }

    func body(content base: Content) -> some View {
        base
            .accessibilityHidden(isPresented)
            .allowsHitTesting(!isPresented)
            .overlay {
                ZStack(alignment: .bottom) {
                    if isPresented {
                        Palette.scrim
                            .ignoresSafeArea(.container)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        sheet.transition(.move(edge: .bottom))
                    }
                }
                .animation(Self.curve, value: isPresented)
            }
            .onChange(of: isPresented) { was, now in
                if now { drag = 0 }
                if was && !now { onDismiss() }
            }
    }

    private func close() { isPresented = false }

    private var sheet: some View {
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
        .offset(y: drag)
        .simultaneousGesture(
            DragGesture()
                .onChanged { drag = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                        close()
                    } else {
                        withAnimation(Self.curve) { drag = 0 }
                    }
                })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cindySheet")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    /// The subtitle and the content, 18 below the title's line, capped at 60% of the height.
    @ViewBuilder private var scrollingBody: some View {
        if subtitle != nil || SheetContent.self != EmptyView.self {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let subtitle {
                        Text(subtitle).cindy(.callout).padding(.top, 5)
                    }
                    content().padding(.top, SheetContent.self == EmptyView.self ? 0 : 18)
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
            close()
        }
        .buttonStyle(CindyPrimaryButtonStyle())
        .accessibilityIdentifier("sheetPrimary")
    }

    private func secondaryButton(_ button: SheetButton) -> some View {
        Button(button.title) {
            button.action()
            if secondaryDismisses { close() }
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

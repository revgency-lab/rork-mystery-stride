//
//  NoirPopup.swift
//  MysteryRun
//
//  In-house modal furniture. The system alert and confirmation dialog are
//  instantly recognisable as iOS chrome, which snaps the detective straight out
//  of a 1940s case file. These are the same interactions dressed in our own ink,
//  brass and paper.
//

import SwiftUI

// MARK: - Presentation

extension View {
    /// Presents `popup` over the view on a dimmed backdrop, dismissible by tapping
    /// outside it.
    func noirPopup<PopupContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder popup: @escaping () -> PopupContent
    ) -> some View {
        modifier(NoirPopupModifier(isPresented: isPresented, popup: popup))
    }

    /// Item-driven variant, for popups whose content is whatever was tapped.
    func noirPopup<Item: Identifiable, PopupContent: View>(
        item: Binding<Item?>,
        @ViewBuilder popup: @escaping (Item) -> PopupContent
    ) -> some View {
        modifier(NoirPopupItemModifier(item: item, popup: popup))
    }
}

private struct NoirPopupModifier<PopupContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let popup: () -> PopupContent

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                NoirPopupBackdrop { isPresented = false }
                NoirPopupFrame { popup() }
            }
        }
        .animation(NoirPopupMetrics.animation, value: isPresented)
    }
}

private struct NoirPopupItemModifier<Item: Identifiable, PopupContent: View>: ViewModifier {
    @Binding var item: Item?
    let popup: (Item) -> PopupContent

    func body(content: Content) -> some View {
        ZStack {
            content

            if let item {
                NoirPopupBackdrop { self.item = nil }
                NoirPopupFrame { popup(item) }
            }
        }
        .animation(NoirPopupMetrics.animation, value: item?.id)
    }
}

enum NoirPopupMetrics {
    static let animation: Animation = .spring(response: 0.34, dampingFraction: 0.84)
}

/// Dimmed, softly blurred scrim. Tapping it dismisses.
private struct NoirPopupBackdrop: View {
    let onDismiss: () -> Void

    var body: some View {
        Rectangle()
            .fill(.black.opacity(0.62))
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture(perform: onDismiss)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Dismiss")
    }
}

/// Centres popup content and keeps it readable at any text size or content length.
private struct NoirPopupFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaPadding(.horizontal, 22)
        .safeAreaPadding(.vertical, 40)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .zIndex(1)
    }
}

// MARK: - Confirmation

/// Noir replacement for `confirmationDialog`: a stamped case-file card with one
/// weighted action and a way out.
struct NoirConfirmCard: View {
    let stamp: String
    let title: String
    let message: String
    let symbolName: String
    let confirmTitle: String
    var isDestructive: Bool = true
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var accent: Color { isDestructive ? Theme.evidenceRed : Theme.brass }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: symbolName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 58, height: 58)
                    .background(accent.opacity(0.12), in: .circle)
                    .overlay { Circle().strokeBorder(accent.opacity(0.45), lineWidth: 1) }

                Text(stamp.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .kerning(2.4)
                    .foregroundStyle(accent.opacity(0.9))

                Text(title)
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 22)

            Rectangle()
                .fill(Theme.inkStroke)
                .frame(height: 1)

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(isDestructive ? Color.white : Color(red: 0.11, green: 0.08, blue: 0.02))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accent, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("Keep Going")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Theme.inkStroke, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Theme.inkElevated, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
    }
}

// MARK: - Clue detail

/// What a clue actually was, opened by tapping its node on the map.
///
/// Collected evidence shows its full story fragment; evidence still out there
/// shows only how far off it is, so the map can't be used to read ahead.
struct MapClueCard: View {
    let clue: Clue
    /// Distance from the detective right now, when a position is known.
    let distance: Double?
    let onClose: () -> Void

    private var accent: Color { clue.isPivotal ? Theme.violet : Theme.brass }

    var body: some View {
        VStack(spacing: 0) {
            header

            if clue.isFound {
                foundBody
            } else {
                pendingBody
            }
        }
        .background(Theme.inkElevated, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(clue.isFound ? accent.opacity(0.35) : Theme.inkStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ClueBadge(index: clue.index, found: clue.isFound, diameter: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(clue.isFound ? "Evidence \(clue.index)" : "Evidence \(clue.index) · Sealed")
                    .font(.system(size: 10, weight: .black))
                    .kerning(1.8)
                    .foregroundStyle(clue.isFound ? accent : Theme.textSecondary)

                Text(clue.isFound ? clue.title : "Not yet examined")
                    .font(.system(.headline, design: .serif, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    private var foundBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            EvidenceNote(fragment: clue.fragment, compact: true)

            VStack(alignment: .leading, spacing: 6) {
                Label(clue.discovery, systemImage: clue.symbolName)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let foundAt = clue.foundAt {
                    Label(foundAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                }
            }

            if clue.isPivotal {
                Label("Pivotal evidence", systemImage: "star.fill")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.violet.opacity(0.14), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    private var pendingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(distanceLine)
                .font(.system(.title3, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.brass)

            Text("Walk into this spot to examine what's waiting there. Its contents stay sealed until you do.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    private var distanceLine: String {
        guard let distance else { return "Distance unknown" }
        return "\(distance.proximityString) from here"
    }
}

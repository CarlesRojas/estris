import SwiftUI

/// A pile of cards: the selected one in front, the next few peeking out above it, each
/// smaller and showing less the further back it is. Moving on drops the front card down
/// while it shrinks, then slides it up behind the pile, never fading it.
struct StackView: View {
    /// How far each card's top sits above the front card's top. Gaps shrink with depth.
    private static let peeks: [CGFloat] = [0, 24, 42, 55, 63]
    private static let scales: [CGFloat] = [1, 0.94, 0.89, 0.85, 0.82]
    private static var maxDepth: Int { peeks.count - 1 }
    private static let dropDuration = 0.18
    private static let returnDuration = 0.26

    private enum Phase: Equatable {
        case front
        case down
        case back(depth: Int)
    }

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings
    @State private var phase = Phase.front
    /// Which departure `phase` belongs to; a new one starts at the front.
    @State private var phaseOwner: UUID?

    private var width: CGFloat { settings.stackWidth }
    private var height: CGFloat { settings.stackHeight }

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                EntryCard(item: nil, width: width, height: height)
            } else {
                ForEach(pileSlots, id: \.item.id) { slot in
                    EntryCard(item: slot.item, width: width, height: height, isSelected: slot.depth == 0)
                        .clipActions(slot.item, trashInset: 22)
                        .scaleEffect(Self.scales[slot.depth], anchor: .top)
                        .offset(y: -Self.peeks[slot.depth])
                        .zIndex(Double(-slot.depth))
                        // Hand-offs with the separately animated departing card must be seamless.
                        .transition(.identity)
                }
                if let departing = state.departing {
                    departingCard(departing.item, phase: phaseOwner == departing.id ? phase : .front)
                }
            }
        }
        .frame(width: width + 120, height: height + 250)
        .animation(.spring(response: 0.4, dampingFraction: 1), value: state.position)
        .onChange(of: state.departing?.id) { id in
            animateDeparture(id)
        }
    }

    private var pileSlots: [(item: ClipItem, depth: Int)] {
        let count = state.items.count
        return state.items.enumerated().compactMap { index, item in
            let depth = ((index - state.selected) % count + count) % count
            guard depth <= Self.maxDepth, item.id != state.departing?.item.id else { return nil }
            return (item, depth)
        }
    }

    private func departingCard(_ item: ClipItem, phase: Phase) -> some View {
        let (scale, offset, inFront): (CGFloat, CGFloat, Bool) = switch phase {
        case .front: (1, 0, true)
        case .down: (0.86, height * 0.55, true)
        case .back(let depth): (Self.scales[depth], -Self.peeks[depth], false)
        }
        return EntryCard(item: item, width: width, height: height)
            .scaleEffect(scale, anchor: .top)
            .offset(y: offset)
            // In front while it drops, then straight behind the pile for the trip back up.
            .zIndex(inFront ? 10 : -50)
            .transition(.identity)
            .allowsHitTesting(false)
    }

    private func animateDeparture(_ id: UUID?) {
        guard let id else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            phaseOwner = id
            phase = .front
        }
        let backDepth = min(state.items.count - 1, Self.maxDepth)

        Task { @MainActor in
            // Let the card show in front once before it starts moving.
            await Task.yield()
            guard state.departing?.id == id else { return }
            withAnimation(.easeIn(duration: Self.dropDuration)) { phase = .down }

            try? await Task.sleep(nanoseconds: UInt64(Self.dropDuration * 1_000_000_000))
            guard state.departing?.id == id else { return }
            withAnimation(.easeOut(duration: Self.returnDuration)) { phase = .back(depth: backDepth) }

            try? await Task.sleep(nanoseconds: UInt64(Self.returnDuration * 1_000_000_000))
            guard state.departing?.id == id else { return }
            withTransaction(instant) { state.departing = nil }
        }
    }
}

extension String {
    /// Trimmed, with line breaks shown as ⏎ so one-line previews stay meaningful.
    var singleLine: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ⏎ ")
    }
}

//
//  FlowView.swift
//  SwiftUI-Flows
//
//  Created by Mark Onyschuk on 6/27/25.
//  Copyright 2025 by Dimension North Inc. All Rights Reserved.
//

import SwiftUI
import Observation

// MARK: - Flow View Components

/// A container view that manages and animates transitions for a navigation flow.
///
/// `FlowView` observes a `Flow` object and automatically renders the appropriate view for the
/// current step. It handles the transitions between steps, including a sophisticated mechanism for
/// "floating" designated UI elements across view changes.
public struct FlowView<F: Flow, Content: View>: View {
    /// The flow controller object that drives the navigation.
    private var flow: F

    /// A view builder that constructs the view for a given step.
    private let content: (F.Step) -> Content

    /// The current `UniqueStep` being displayed. This state drives the view transitions.
    @State private var currentStep: UniqueStep<F.Step>

    /// The animation properties for the current transition.
    @State private var currentAnimation: FlowAnimation?

    /// The set of IDs for views that are currently "floating" during a transition.
    @State private var floatingIDs: Set<AnyHashable> = []

    /// A dictionary containing the layout and logic for all views marked with the `.float()` modifier.
    @State private var floatableItems: [AnyHashable: FloatableDecision] = [:]

    /// Initializes a `FlowView`.
    /// - Parameters:
    ///   - flow: An instance of a class conforming to the `Flow` protocol.
    ///   - content: A view builder closure that takes the current `F.Step` and returns a view to display.
    public init(_ flow: F, @ViewBuilder content: @escaping (F.Step) -> Content) {
        self.flow = flow
        self.content = content

        let initialTransition = AnyTransition.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity))
        _currentStep = State(initialValue: flow.history.top)
        _currentAnimation = State(
            initialValue: FlowAnimation(
                id: flow.history.top.id, direction: .forward, transition: initialTransition))
    }

    public var body: some View {
        ZStack {
            content(currentStep.step)
                .environment(\.flowAnimation, currentAnimation)
                .environment(\.floatingIDs, floatingIDs)
        }
        .overlay(floatingOverlay)
        .backgroundPreferenceValue(FloatableContentPreferenceKey.self) { preferences in
            // This preference key collector runs whenever a child view marked as "floatable"
            // changes. It gathers all floatable items into the `floatableItems` state variable.
            let equatableData = preferences.mapValues { $0.data }
            Color.clear
                .onAppear {
                    self.floatableItems = preferences
                }
                .onChange(of: equatableData) {
                    self.floatableItems = preferences
                }
        }
        .onChange(of: flow.history.top) {
            // This is the main trigger for transitions.
            let oldStep = currentStep.step
            let newStep = flow.history.top
            let direction = flow.history.direction

            // Determine which views should float based on their custom logic.
            let idsToFloat = Set(
                floatableItems.compactMap { id, decision in
                    decision.logic(oldStep, newStep.step) ? id : nil
                })
            self.floatingIDs = idsToFloat

            // Define the push/pop animation.
            let transition: AnyTransition =
                (direction == .forward)
                ? .asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading).combined(with: .opacity))
                : .asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .trailing).combined(with: .opacity))

            if let currentID = currentAnimation?.id {
                currentAnimation = FlowAnimation(
                    id: currentID, direction: direction, transition: transition
                )
            }

            // Animate the change.
            DispatchQueue.main.async {
                let animation = FlowAnimation(
                    id: newStep.id, direction: direction, transition: transition
                )

                withAnimation(.easeInOut(duration: 0.4)) {
                    self.currentStep = newStep
                    self.currentAnimation = animation
                } completion: {
                    // Once the animation is complete, clear the floating items.
                    self.floatingIDs.removeAll()
                }
            }
        }
    }

    /// The overlay that renders the views that are currently floating.
    @ViewBuilder
    private var floatingOverlay: some View {
        let items = Array(floatableItems.values.map(\.data))
        
        ForEach(items) { item in
            if floatingIDs.contains(item.id) {
                item.view
                    .frame(
                        width: item.frame.width,
                        height: item.frame.height
                    )
                    .position(
                        x: item.frame.minX + item.frame.width / 2,
                        y: item.frame.minY + item.frame.height / 2
                    )
            }
        }
    }
}

/// A wrapper view that applies the correct transition animation to the content of a flow step.
///
/// You should wrap the content for each step inside an `AnimatedFlowContent` block within the
/// `FlowView`'s content closure. This ensures that the entire view for a step is treated as a
/// single, identifiable unit for transitions.
public struct AnimatedFlowContent<Content: View>: View {
    private let content: () -> Content

    /// Creates an animated content block.
    /// - Parameter content: A view builder for the content to be animated.
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    @Environment(\.flowAnimation) private var flowAnimation

    public var body: some View {
        Group {
            if let flowAnimation {
                content()
                    .id(flowAnimation.id)
                    .transition(flowAnimation.transition)
            } else {
                content()
            }
        }
    }
}

// MARK: - Floating Content Infrastructure (Internal)

/// A struct that holds the data and logic for a single floatable view.
///
/// This is the value collected by the `FloatableContentPreferenceKey`.
struct FloatableDecision {
    /// The data representing the floatable view.
    let data: FloatingContentData
    /// A type-erased closure that determines if the view should float between two given steps.
    let logic: (Any, Any) -> Bool
}

/// A preference key to collect `FloatableDecision` data from all floatable views
/// in the hierarchy and pass it up to the parent `FlowView`.
struct FloatableContentPreferenceKey: PreferenceKey {
    typealias Value = [AnyHashable: FloatableDecision]
    static var defaultValue: Value { [:] }
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

/// A struct containing the necessary data to render a floating view.
struct FloatingContentData: Equatable, Identifiable {
    /// The unique ID of the floatable view.
    let id: AnyHashable
    /// The view's frame in the global coordinate space.
    let frame: CGRect
    /// A type-erased `AnyView` holding the view's content.
    let view: AnyView

    static func == (lhs: FloatingContentData, rhs: FloatingContentData) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame
    }
}

/// Environment key to pass the set of currently floating IDs down the view hierarchy.
private struct FloatingIDsKey: EnvironmentKey {
    static var defaultValue: Set<AnyHashable> { [] }
}

extension EnvironmentValues {
    /// The set of IDs corresponding to views that should be in a "floating" state.
    fileprivate var floatingIDs: Set<AnyHashable> {
        get { self[FloatingIDsKey.self] }
        set { self[FloatingIDsKey.self] = newValue }
    }
}

/// A private view that wraps content designated as "floatable".
///
/// It captures the content's geometry, passes the necessary data up via a preference key,
/// and hides the original content when it is being rendered in the `FlowView`'s floating overlay.
private struct FloatingFlowContent<F: Flow, Content: View>: View {
    let id: AnyHashable
    let shouldFloat: (F.Step, F.Step) -> Bool
    let content: Content

    @Environment(\.floatingIDs) private var floatingIDs

    init(
        _ id: AnyHashable, in flow: F, shouldFloat: @escaping (F.Step, F.Step) -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.shouldFloat = shouldFloat
        self.content = content()
    }

    var body: some View {
        ZStack {
            // The original content is made transparent when its "clone" is floating in the overlay.
            content.opacity(floatingIDs.contains(id) ? 0 : 1)

            // A GeometryReader captures the view's frame and reports it up the hierarchy.
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FloatableContentPreferenceKey.self,
                    value: [
                        id: FloatableDecision(
                            data: FloatingContentData(
                                id: id,
                                frame: geometry.frame(in: .global),
                                view: AnyView(content)
                            ),
                            logic: { anyFrom, anyTo in
                                // Type-erase the logic closure for storage in the preference key.
                                guard let from = anyFrom as? F.Step, let to = anyTo as? F.Step
                                else { return false }
                                return shouldFloat(from, to)
                            }
                        )
                    ])
            }
        }
    }
}

extension View {
    /// Makes the view "float" between all flow steps.
    ///
    /// When a transition occurs, the view will not be part of the fade/slide animation. Instead, it will
    /// remain visible and animate its position and size to match the frame of the corresponding view
    /// in the destination step.
    ///
    /// - Parameters:
    ///   - id: A unique, hashable identifier for this view. Must be stable across transitions.
    ///   - flow: The `Flow` instance this view is part of.
    /// - Returns: A view modified to float during transitions.
    public func float<F: Flow>(_ id: AnyHashable, in flow: F) -> some View {
        FloatingFlowContent(id, in: flow, shouldFloat: { _, _ in true }) { self }
    }

    /// Makes the view "float" only when transitioning between steps that are members of a given set.
    ///
    /// This is useful for floating elements only within a specific "chapter" or section of a flow.
    /// The view will float if and only if both the starting step and the destination step are
    /// contained within the `memberOf` set.
    ///
    /// - Parameters:
    ///   - id: A unique, hashable identifier for this view.
    ///   - flow: The `Flow` instance this view is part of.
    ///   - memberOf: A set of steps. The view will only float for transitions between steps in this set.
    /// - Returns: A view modified to float during specific transitions.
    public func float<F: Flow>(_ id: AnyHashable, in flow: F, between memberOf: Set<F.Step>)
        -> some View
    {
        let logic: (F.Step, F.Step) -> Bool = { from, to in
            memberOf.contains(from) && memberOf.contains(to)
        }
        return FloatingFlowContent(id, in: flow, shouldFloat: logic) { self }
    }

    /// Makes the view "float" between flow steps based on custom logic.
    ///
    /// This is the most powerful variant, allowing for complex, data-driven checks. The view will
    /// float if the `shouldFloat` closure returns `true`.
    ///
    /// - Parameters:
    ///   - id: A unique, hashable identifier for this view.
    ///   - flow: The `Flow` instance this view is part of.
    ///   - shouldFloat: A closure that takes the `from` and `to` steps and returns `true` if the view should float for that transition.
    /// - Returns: A view modified to float based on custom logic.
    public func float<F: Flow>(
        _ id: AnyHashable, in flow: F, shouldFloat: @escaping (F.Step, F.Step) -> Bool
    ) -> some View {
        FloatingFlowContent(id, in: flow, shouldFloat: shouldFloat) { self }
    }
}

/// Executes a block of code within a `withAnimation` block and asynchronously awaits the animation's completion.
///
/// - Parameters:
///   - duration: The duration of the animation.
///   - changes: A closure containing the state changes to animate.
@MainActor
public func awaitAnimation(duration: TimeInterval, _ changes: @escaping () -> Void) async {
    await withCheckedContinuation { continuation in
        withAnimation(.easeInOut(duration: duration)) { changes() }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { continuation.resume() }
    }
}

/// A struct containing the animation parameters for a flow transition.
private struct FlowAnimation: Equatable {
    let id: UUID
    let direction: FlowDirection
    let transition: AnyTransition
    static func == (lhs: FlowAnimation, rhs: FlowAnimation) -> Bool {
        lhs.id == rhs.id && lhs.direction == rhs.direction
    }
}

/// Environment key for passing `FlowAnimation` data to `AnimatedFlowContent`.
private struct FlowAnimationKey: EnvironmentKey {
    static var defaultValue: FlowAnimation? { nil }
}
extension EnvironmentValues {
    fileprivate var flowAnimation: FlowAnimation? {
        get { self[FlowAnimationKey.self] }
        set { self[FlowAnimationKey.self] = newValue }
    }
}

extension CaseIterable where Self: Equatable, AllCases: BidirectionalCollection {
    /// Returns the next case in the enum's `allCases` collection, or `nil` if the current case is the last.
    public var next: Self? {
        guard let currentIndex = Self.allCases.firstIndex(of: self),
            currentIndex < Self.allCases.index(before: Self.allCases.endIndex)
        else { return nil }
        return Self.allCases[Self.allCases.index(after: currentIndex)]
    }
    /// Returns the previous case in the enum's `allCases` collection, or `nil` if the current case is the first.
    public var previous: Self? {
        guard let currentIndex = Self.allCases.firstIndex(of: self),
            currentIndex > Self.allCases.startIndex
        else { return nil }
        return Self.allCases[Self.allCases.index(before: currentIndex)]
    }
}

// MARK: - PREVIEW

private enum PreviewStep: Int, Equatable, Sendable {
    case welcome, features, summary
}

@Observable
private final class PreviewFlow: Flow {
    typealias Step = PreviewStep
    var history: FlowHistory<Step>
    var hasNext: Bool { step != .summary }

    func content(for step: Step) -> [String: String] {
        switch step {
        case .welcome: return ["title": "Welcome!", "art": "🎨"]
        case .features: return ["title": "Welcome!", "art": "✅"]
        case .summary: return ["title": "Summary", "art": "✅"]
        }
    }

    init() { self.history = FlowHistory(.welcome) }

    @MainActor func next() async throws {
        let nextStep: Step? =
            switch step {
            case .welcome: .features
            case .features: .summary
            case .summary: nil
            }
        if let nextStep { history.push(nextStep) }
    }
}

private struct PreviewStepView: View {
    let color: Color
    let content: [String: String]
    let flow: PreviewFlow

    var body: some View {
        VStack(spacing: 40) {
            Text(content["title", default: ""])
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 5)
                // The logic here is data-driven ("is the title text the same?"), so the closure is still
                // the correct tool for this specific preview.
                .float("title", in: flow) { from, to in
                    flow.content(for: from)["title"] == flow.content(for: to)["title"]
                }

            Text(content["art", default: ""])
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 5)
                // If we had a group of steps called "Content Steps" where this art was present,
                // the new API would be perfect:
                // .float("art", in: flow, when: [.features, .summary])
                .float("art", in: flow) { from, to in
                    flow.content(for: from)["art"] == flow.content(for: to)["art"]
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.ignoresSafeArea())
    }
}

struct PreviewContainer: View {
    @State private var flow = PreviewFlow()

    var body: some View {
        FlowView(flow) { step in
            VStack {
                AnimatedFlowContent {
                    let content = flow.content(for: step)
                    switch step {
                    case .welcome: PreviewStepView(color: .indigo, content: content, flow: flow)
                    case .features: PreviewStepView(color: .teal, content: content, flow: flow)
                    case .summary: PreviewStepView(color: .orange, content: content, flow: flow)
                    }
                }
                HStack(spacing: 20) {
                    Button("Back", action: flow.previous).disabled(!flow.hasPrevious)
                    Button("Next") { Task { try? await flow.next() } }.disabled(!flow.hasNext)
                }
                .buttonStyle(.bordered).controlSize(.large).tint(.white).padding().shadow(
                    radius: 10)
            }
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }
}

#Preview {
    PreviewContainer()
}

# SwiftUI-Flows

![Swift 5.9+](https://img.shields.io/badge/swift-5.9+-orange.svg)![Platforms iOS 17+ | macOS 14+](https://img.shields.io/badge/platforms-iOS%2017+%20%7C%20macOS%2014+-blue.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful, generic, and declarative navigation system for SwiftUI.

`SwiftUI-Flows` provides a robust solution for building multi-step user interfaces like onboarding flows, wizards, and surveys. It's designed to be state-driven, easily testable, and features a unique API for creating seamless "floating" view transitions.

## Features

-   ✅ **Declarative & State-Driven:** Your UI is a direct function of your navigation state.
-   🚀 **Automatic Animated Transitions:** Handles forward and backward transitions with customizable animations out of the box.
-   ✨ **Floating Views API:** Persist and animate UI elements (like logos, titles, or buttons) across view transitions for a polished, professional feel.
-   🧩 **Generic & Type-Safe:** Built with generics to work with any `Equatable` step type (e.g., enums), ensuring type safety.
-   📦 **Lightweight & Simple Integration:** Drop it in as a Swift Package and get started in minutes.

https://github.com/user-attachments/assets/2e90c5cd-659f-442a-a92c-567e9b08f427

## Requirements

-   iOS 17.0+
-   macOS 14.0+
-   Swift 5.9+

## Installation

You can add `SwiftUI-Flows` to your Xcode project as a package dependency.

1.  From the **File** menu, select **Add Packages...**
2.  Enter the repository URL: `https://github.com/your-username/SwiftUI-Flows.git` (replace with your actual URL)
3.  Select the **Up to Next Major** version rule.
4.  Click **Add Package** and add the `SwiftUI-Flows` library to your app target.

## Core Concepts

The library is built around two main components:

1.  **`Flow` Protocol:** An `Observable` object you create to manage the state and business logic of your navigation. It holds the navigation `history` and defines the `next()` and `previous()` actions.
2.  **`FlowView`:** A SwiftUI container view that observes your `Flow` object. It automatically renders the correct view for the current step and manages all transitions and animations.

## Usage Example

Here’s how to set up a simple three-step onboarding flow.

### Step 1: Define Your Steps

First, define the steps of your flow using an enum.

```swift
import SwiftUI_Flows

enum OnboardingStep: Equatable {
    case welcome
    case features
    case ready
}
```

### Step 2: Create a Flow Controller

Next, create an `@Observable` class that conforms to the `Flow` protocol. This class will manage your navigation state.

```swift
import SwiftUI
import SwiftUI_Flows

@Observable
final class OnboardingFlow: Flow {
    typealias Step = OnboardingStep
    
    // The history stack is the source of truth for the navigation.
    var history: FlowHistory<Step>

    // Logic to determine if the user can advance.
    var hasNext: Bool {
        step != .ready
    }

    init() {
        // Start the flow at the .welcome step.
        self.history = FlowHistory(.welcome)
    }
    
    @MainActor
    func next() async throws {
        let nextStep: Step? = switch step {
        case .welcome:  .features
        case .features: .ready
        case .ready:    nil
        }
        
        if let nextStep {
            history.push(nextStep)
        }
    }
}
```

### Step 3: Build the UI with `FlowView`

In your SwiftUI view, create an instance of your flow controller and pass it to `FlowView`. Use a `switch` statement to provide the correct view for each step.

```swift
import SwiftUI
import SwiftUI_Flows

struct OnboardingContainerView: View {
    @State private var flow = OnboardingFlow()

    var body: some View {
        FlowView(flow) { step in
            VStack {
                // AnimatedFlowContent ensures the whole view animates as a unit.
                AnimatedFlowContent {
                    switch step {
                    case .welcome:
                        StepView(title: "Welcome!", icon: "👋", color: .indigo, flow: flow)
                    case .features:
                        StepView(title: "Welcome!", icon: "✨", color: .teal, flow: flow)
                    case .ready:
                        StepView(title: "You're All Set", icon: "🚀", color: .orange, flow: flow)
                    }
                }
                
                // Navigation Controls
                HStack {
                    Button("Back", action: flow.previous)
                        .disabled(!flow.hasPrevious)
                    
                    Button("Next") { Task { try? await flow.next() } }
                        .disabled(!flow.hasNext)
                }
                .padding()
            }
        }
    }
}```

### Step 4: Add Floating Views

The magic of `SwiftUI-Flows` is the `.float()` modifier. It allows a view to persist across a transition instead of being removed and re-added.

In your `StepView`, apply the modifier to any element you want to float.

```swift
struct StepView: View {
    let title: String
    let icon: String
    let color: Color
    let flow: OnboardingFlow

    var body: some View {
        VStack(spacing: 40) {
            Text(title)
                .font(.largeTitle.bold())
                // Float this title if the 'title' text is the same between steps.
                .float("title-id", in: flow) { from, to in
                    // Custom logic here
                    let oldTitle = titleForStep(from)
                    let newTitle = titleForStep(to)
                    return oldTitle == newTitle
                }

            Text(icon)
                .font(.system(size: 80))
                // Always float this icon, no matter the step.
                .float("icon-id", in: flow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.ignoresSafeArea())
    }
    
    // Helper to get data for a step (matches logic in the Flow object)
    private func titleForStep(_ step: OnboardingFlow.Step) -> String {
        switch step {
        case .welcome, .features: return "Welcome!"
        case .ready: return "You're All Set"
        }
    }
}
```

## Floating API Reference

There are three ways to use the `.float()` modifier:

1.  **Always Float**
    The view will float during every transition.

    ```swift
    .float("unique-id", in: flow)
    ```

2.  **Float Within a Group of Steps**
    The view will only float if both the `from` and `to` steps are members of the provided set.

    ```swift
    .float("unique-id", in: flow, between: [.features, .ready])
    ```

3.  **Float with Custom Logic**
    Provide a closure to define complex, data-driven floating behavior. The view floats if your closure returns `true`.

    ```swift
    .float("unique-id", in: flow) { fromStep, toStep in
        // Return true if the view should float for this transition
        return viewModel.data(for: fromStep).title == viewModel.data(for: toStep).title
    }
    ```

## License

This package is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

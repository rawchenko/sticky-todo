import Foundation

enum ClassicOnboardingStepID: String {
    case welcome
    case hoverExpand
    case createTask
    case completeTask
    case hoverCollapse
    case finish
}

struct BasicStepContent {
    let title: String
    let body: String
}

struct InteractiveStepContent {
    let title: String
    let body: String
}

struct PanelHoverStepContent {
    let title: String
    let body: String
    let initialCollapsed: Bool
    let targetCollapsed: Bool
}

enum ClassicOnboardingStepKind {
    case basic(BasicStepContent)
    case interactive(InteractiveStepContent)
    case panelHover(PanelHoverStepContent)

    var title: String {
        switch self {
        case .basic(let c): return c.title
        case .interactive(let c): return c.title
        case .panelHover(let c): return c.title
        }
    }

    var body: String {
        switch self {
        case .basic(let c): return c.body
        case .interactive(let c): return c.body
        case .panelHover(let c): return c.body
        }
    }
}

struct ClassicOnboardingStep: Identifiable {
    let id: ClassicOnboardingStepID
    let kind: ClassicOnboardingStepKind
}

extension ClassicOnboardingStep {
    static let defaultFlow: [ClassicOnboardingStep] = [
        ClassicOnboardingStep(
            id: .welcome,
            kind: .basic(BasicStepContent(
                title: "Welcome to FloatList",
                body: "A tiny to-do panel that docks to the edge of your screen — always one glance away, never in the way."
            ))
        ),
        ClassicOnboardingStep(
            id: .hoverExpand,
            kind: .panelHover(PanelHoverStepContent(
                title: "Pops out on hover",
                body: "FloatList collapses into a small handle at the edge. Watch the full panel come back.",
                initialCollapsed: true,
                targetCollapsed: false
            ))
        ),
        ClassicOnboardingStep(
            id: .createTask,
            kind: .interactive(InteractiveStepContent(
                title: "Adding a task",
                body: "The demo types a task and saves it with Return."
            ))
        ),
        ClassicOnboardingStep(
            id: .completeTask,
            kind: .interactive(InteractiveStepContent(
                title: "Checking it off",
                body: "Watch a completed task slide away so only what's left stays in view."
            ))
        ),
        ClassicOnboardingStep(
            id: .hoverCollapse,
            kind: .panelHover(PanelHoverStepContent(
                title: "Tucks back at the edge",
                body: "Once you're done, FloatList slides back to the edge, out of the way.",
                initialCollapsed: false,
                targetCollapsed: true
            ))
        ),
        ClassicOnboardingStep(
            id: .finish,
            kind: .basic(BasicStepContent(
                title: "You're all set",
                body: "FloatList will fly to the edge of your screen. Hover it any time to jump back in."
            ))
        )
    ]
}

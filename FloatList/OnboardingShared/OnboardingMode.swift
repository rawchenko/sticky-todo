import Foundation
import SwiftUI

/// Gates user-interaction paths while the autoplay onboarding demo is
/// mounted. Real app installs `.init(isActive: false)` so every gate is true.
///
/// Interactive onboarding scenes pass `allowed` to re-open specific paths
/// (e.g. Scene 2 lets the user actually type a task while the rest of the
/// panel stays locked).
@MainActor
final class OnboardingMode: ObservableObject {
    /// Individual interaction gates. An interactive scene can pass a set
    /// of these to `init(isActive:allowed:)` to opt-in to exactly the
    /// behaviors it needs — everything else stays locked.
    enum Gate: Hashable {
        case newTodoInput
        case completeToggle
        case rowEditing
        case rowSwipe
        case rowContextMenu
        case dragReorder
        case listDropdown
        case selectionShortcuts
    }

    let isActive: Bool
    /// Mutable so an interactive scene can open a gate mid-flight (e.g.
    /// Scene 2 adds `.newTodoInput` in onAppear) without rebuilding the
    /// whole environment.
    @Published var allowed: Set<Gate>

    /// When set, the todo row with this id renders a pulsing halo around
    /// its checkbox. Used in Scene 2 to draw the user's attention to the
    /// first task's checkbox after they've added it.
    @Published var pulsingCheckboxItemID: UUID?

    init(isActive: Bool, allowed: Set<Gate> = []) {
        self.isActive = isActive
        self.allowed = allowed
        self.pulsingCheckboxItemID = nil
    }

    func open(_ gate: Gate)  { allowed.insert(gate) }
    func close(_ gate: Gate) { allowed.remove(gate) }

    private func gate(_ g: Gate) -> Bool { !isActive || allowed.contains(g) }

    var allowsListDropdownOpen: Bool { gate(.listDropdown) }
    var allowsNewListAction: Bool    { !isActive }
    var allowsListSelection: Bool    { !isActive }
    var allowsListManagement: Bool   { !isActive }
    var allowsListColorPicker: Bool  { !isActive }
    var allowsListReorder: Bool      { !isActive }
    var allowsRowContextMenu: Bool   { gate(.rowContextMenu) }
    var allowsDragReorder: Bool      { gate(.dragReorder) }
    var allowsNewTodoInput: Bool     { gate(.newTodoInput) }
    var allowsCompleteToggle: Bool   { gate(.completeToggle) }
    var allowsRowSwipe: Bool         { gate(.rowSwipe) }
    var allowsRowEditing: Bool       { gate(.rowEditing) }
    var allowsSettings: Bool         { !isActive }
    var allowsEmptyTrash: Bool       { !isActive }
    var allowsShowCompletedToggle: Bool { !isActive }
    var allowsSelectionShortcuts: Bool  { gate(.selectionShortcuts) }
    var allowsUndo: Bool             { !isActive }
    var allowsDeleteList: Bool       { !isActive }
}

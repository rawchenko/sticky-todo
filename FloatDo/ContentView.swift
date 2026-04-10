import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var panelManager: PanelManager
    @State private var newTaskTitle = ""
    @State private var dismissedRecoveryNoticeID: UUID?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let shape = MorphingDockedShape(
                corner: panelManager.currentCorner,
                expansion: expansionProgress
            )

            ZStack(alignment: panelManager.currentCorner.alignment) {
                shape
                    .fill(FloatDoTheme.shell)
                    .shadow(color: FloatDoTheme.shadow.opacity(0.96), radius: PanelMetrics.shadowRadius, y: 4)

                expandedLayer

                collapsedGlyph
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: panelManager.currentCorner.alignment
            )
            .overlay(shape.stroke(FloatDoTheme.border, lineWidth: 1))
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .animation(PanelMotion.stateAnimation, value: panelManager.isCollapsed)
        .animation(PanelMotion.stateAnimation, value: panelManager.currentCorner)
    }

    private var expandedLayer: some View {
        expandedContent
            .opacity(expandedOpacity)
            .scaleEffect(expandedScale, anchor: panelManager.currentCorner.unitPoint)
            .allowsHitTesting(expansionProgress > 0.72)
            .accessibilityHidden(expansionProgress < 0.3)
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header

            if let notice = activeRecoveryNotice {
                recoveryBanner(notice)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            panelDivider

            if sortedItems.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 24))
                        .foregroundStyle(FloatDoTheme.textTertiary)
                    Text("No tasks yet")
                        .font(.system(size: 12))
                        .foregroundStyle(FloatDoTheme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedItems) { item in
                            TodoRowView(
                                item: item,
                                onToggle: { store.toggle(item) },
                                onDelete: { store.delete(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
            }

            panelDivider

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(FloatDoTheme.iconMuted)

                TextField("New task...", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(FloatDoTheme.textPrimary)
                    .focused($isInputFocused)
                    .onSubmit {
                        store.add(title: newTaskTitle)
                        newTaskTitle = ""
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(FloatDoTheme.inputFill)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var collapsedGlyph: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 15, weight: .semibold))
            Capsule()
                .fill(FloatDoTheme.textSecondary)
                .frame(width: 12, height: 2)
            Capsule()
                .fill(FloatDoTheme.textSecondary)
                .frame(width: 12, height: 2)
        }
        .foregroundStyle(FloatDoTheme.textPrimary)
        .frame(width: PanelMetrics.collapsedSize.width, height: PanelMetrics.collapsedSize.height)
        .opacity(collapsedOpacity)
        .scaleEffect(collapsedScale, anchor: panelManager.currentCorner.unitPoint)
        .offset(collapsedOffset)
        .allowsHitTesting(false)
        .accessibilityHidden(expansionProgress > 0.7)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("FloatDo")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FloatDoTheme.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [FloatDoTheme.shellRaised.opacity(0.9), FloatDoTheme.shell],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(FloatDoTheme.divider)
            .frame(height: 1)
    }

    private var expansionProgress: CGFloat {
        panelManager.isCollapsed ? 0 : 1
    }

    private var expandedOpacity: CGFloat {
        let adjusted = max(0, (expansionProgress - 0.18) / 0.82)
        return adjusted * adjusted
    }

    private var expandedScale: CGFloat {
        0.975 + (0.025 * expansionProgress)
    }

    private var collapsedOpacity: CGFloat {
        let inverse = 1 - expansionProgress
        return min(1, inverse * 1.3)
    }

    private var collapsedScale: CGFloat {
        1 - (0.1 * expansionProgress)
    }

    private var collapsedOffset: CGSize {
        CGSize(
            width: transitionOffset.width * expansionProgress * 0.32,
            height: transitionOffset.height * expansionProgress * 0.32
        )
    }

    private var transitionOffset: CGSize {
        let distance = PanelMotion.transitionDistance

        switch panelManager.currentCorner {
        case .topLeft:
            return CGSize(width: -distance, height: -distance)
        case .topRight:
            return CGSize(width: distance, height: -distance)
        case .bottomLeft:
            return CGSize(width: -distance, height: distance)
        case .bottomRight:
            return CGSize(width: distance, height: distance)
        }
    }

    private var sortedItems: [TodoItem] {
        store.items.sorted { a, b in
            if a.isCompleted != b.isCompleted {
                return !a.isCompleted
            }
            return a.createdAt < b.createdAt
        }
    }

    private var activeRecoveryNotice: TodoStoreRecoveryNotice? {
        guard let notice = store.recoveryNotice else { return nil }
        return dismissedRecoveryNoticeID == notice.id ? nil : notice
    }

    @ViewBuilder
    private func recoveryBanner(_ notice: TodoStoreRecoveryNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FloatDoTheme.warningText)

                if let backupURL = notice.backupURL {
                    Text("Backup: \(backupURL.lastPathComponent)")
                        .font(.system(size: 10))
                        .foregroundStyle(FloatDoTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Button {
                dismissedRecoveryNoticeID = notice.id
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FloatDoTheme.textPrimary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(FloatDoTheme.controlFill)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FloatDoTheme.warningBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FloatDoTheme.warningBorder, lineWidth: 1)
        )
    }
}

import SwiftUI

struct SpaceBarView: View {
    let spaceCollection: SpaceCollection
    var onNewSpace: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(spaceCollection.spaces) { space in
                        SpaceBarItemView(
                            space: space,
                            isActive: space.id == spaceCollection.activeSpaceID,
                            onSelect: { spaceCollection.activateSpace(id: space.id) },
                            onClose: { spaceCollection.removeSpace(id: space.id) }
                        )
                    }
                }
                .padding(.horizontal, 6)
            }
            .dropDestination(for: SpaceDragItem.self) { items, _ in
                guard let item = items.first,
                      let sourceIndex = spaceCollection.spaces.firstIndex(where: { $0.id == item.spaceID }) else {
                    return false
                }
                let destIndex = spaceCollection.spaces.count - 1
                if sourceIndex != destIndex {
                    spaceCollection.reorderSpace(from: sourceIndex, to: destIndex)
                }
                return true
            }

            Spacer()

            Button(action: onNewSpace) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .accessibilityLabel("New space")
            .padding(.trailing, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }
}

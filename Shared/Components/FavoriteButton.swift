import SwiftUI

struct FavoriteButton: View {
    let isFavorite: Bool
    let isUpdating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(
                            isFavorite ? Color.pink : Color.secondary
                        )
                }
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .accessibilityLabel(isFavorite ? "取消喜欢" : "添加喜欢")
        .accessibilityValue(isFavorite ? "已喜欢" : "未喜欢")
    }
}

import SwiftUI

struct LyricRubyText: View {
    let rows: [LyricRubyRow]
    let fontSize: CGFloat
    let romanizationFontSize: CGFloat
    let fontWeight: LyricsFontWeight
    let primaryColor: Color
    let romanizationOpacity: Double
    let alignment: SynchronizedLyricTextAlignment
    let annotationExpansion: CGFloat
    let playbackTime: TimeInterval
    let rendererStyle: LyricGlowTextRenderer.Style
    let appliesTimingEffects: Bool
    let timingEffectsStrength: Double

    var body: some View {
        VStack(
            alignment: alignment.horizontalAlignment,
            spacing: max(fontSize * 0.06, 2)
        ) {
            ForEach(rows) { row in
                LyricAnnotationLayout(
                    expansion: annotationExpansion,
                    spacing:
                        LyricAnnotationMetrics.verticalSpacing
                ) {
                    originalView(for: row)
                    romanizationView(for: row)
                }
                .frame(
                    width: row.width,
                    alignment: .leading
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: alignment.frameAlignment
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.plainOriginalText)
            }
        }
    }

    private func originalView(
        for row: LyricRubyRow
    ) -> some View {
        row.originalText
            .font(
                .system(
                    size: fontSize,
                    weight: fontWeight.swiftUIWeight
                )
            )
            .foregroundStyle(primaryColor)
            .fixedSize()
            .textRenderer(
                LyricGlowTextRenderer(
                    playbackTime: playbackTime,
                    style: rendererStyle,
                    layoutConfiguration: .init(
                        width: nil,
                        centersLines: false,
                        trailingVisualOverflow:
                            row.originalTrailingVisualOverflow
                    ),
                    appliesTimingEffects: appliesTimingEffects,
                    timingEffectsStrength: timingEffectsStrength
                )
            )
            .frame(
                width: row.width,
                alignment: .leading
            )
    }

    private func romanizationView(
        for row: LyricRubyRow
    ) -> some View {
        row.romanizationText
            .font(
                .system(
                    size: romanizationFontSize,
                    weight: fontWeight.swiftUIWeight
                )
            )
            .foregroundStyle(
                primaryColor.opacity(romanizationOpacity)
            )
            .fixedSize()
            .textRenderer(
                LyricRomanizationTextRenderer(
                    playbackTime: playbackTime,
                    unplayedOpacity: rendererStyle.unplayedOpacity,
                    trailingVisualOverflow:
                        row.romanizationTrailingVisualOverflow,
                    appliesTimingEffects: appliesTimingEffects,
                    timingEffectsStrength: timingEffectsStrength
                )
            )
            .frame(
                width: row.width,
                alignment: .leading
            )
            .opacity(annotationExpansion)
            .accessibilityHidden(true)
    }
}

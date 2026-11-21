import SwiftUI

enum TempoTheme {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.13, green: 0.17, blue: 0.16)
    static let muted = Color(red: 0.40, green: 0.44, blue: 0.41)
    static let line = Color(red: 0.87, green: 0.88, blue: 0.84)
    static let lime = Color(red: 0.82, green: 0.94, blue: 0.42)
    static let mint = Color(red: 0.67, green: 0.87, blue: 0.80)
    static let dark = Color(red: 0.08, green: 0.12, blue: 0.11)
}

struct Eyebrow: View {
    let text: String
    var color: Color = TempoTheme.muted
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(2).foregroundStyle(color)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var color: Color = TempoTheme.ink
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(.headline, design: .rounded))
                Spacer()
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 24).frame(minHeight: 60)
            .foregroundStyle(foreground).background(color, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

struct TempoMark: View {
    var size: CGFloat = 32
    var color: Color = TempoTheme.ink
    var body: some View {
        ZStack {
            Circle().trim(from: 0.08, to: 0.91).stroke(color, style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Capsule().fill(color).frame(width: size * 0.09, height: size * 0.30).offset(y: -size * 0.10)
                .rotationEffect(.degrees(35))
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct StepRow: View {
    let step: RoutineStep
    let number: Int
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(step.kind == .rest ? TempoTheme.mint.opacity(0.35) : TempoTheme.paper)
                Image(systemName: step.symbol).font(.system(size: 23, weight: .medium))
                    .accessibilityLabel(step.kind == .rest ? "Rest" : "\(step.selectedIcon.title) exercise icon")
            }.frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.displayName).font(.system(.body, design: .rounded, weight: .semibold))
                Text(step.kind == .rest ? "Rest" : "Exercise \(number)").font(.caption).foregroundStyle(TempoTheme.muted)
            }
            Spacer(minLength: 8)
            Text(DurationText.clock(step.seconds)).font(.system(.subheadline, design: .monospaced, weight: .medium))
        }
        .foregroundStyle(TempoTheme.ink).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct IconChoiceRow: View {
    let title: String
    let icon: ExerciseIcon

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon.symbol).font(.system(size: 24)).frame(width: 38, height: 40)
                .foregroundStyle(TempoTheme.ink).accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(icon.title).font(.subheadline).foregroundStyle(TempoTheme.muted)
        }.padding(.vertical, 3)
    }
}

struct ExerciseIconPicker: View {
    @Binding var selection: ExerciseIcon
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Find your kind of movement.")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 12)], spacing: 12) {
                    ForEach(ExerciseIcon.allCases) { icon in
                        Button {
                            selection = icon
                            dismiss()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: icon.symbol).font(.system(size: 33))
                                    .frame(height: 42)
                                Text(icon.title).font(.system(.caption, design: .rounded, weight: .semibold))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                            .background(selection == icon ? TempoTheme.lime : .white, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(alignment: .topTrailing) {
                                if selection == icon {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).padding(9)
                                }
                            }
                        }
                        .buttonStyle(.plain).foregroundStyle(TempoTheme.ink)
                        .accessibilityLabel("\(icon.title) icon")
                        .accessibilityIdentifier("icon-\(icon.rawValue)")
                        .accessibilityAddTraits(selection == icon ? .isSelected : [])
                    }
                }
            }.padding(24)
        }
        .tempoBackground().navigationTitle("Choose an icon").navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func tempoBackground() -> some View { background(TempoTheme.paper.ignoresSafeArea()) }
}

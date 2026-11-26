import SwiftUI

struct RoutineLibraryView: View {
    @Bindable var store: RoutineStore
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 9) {
                        TempoMark()
                        Text("tempo").font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-1)
                        Spacer()
                        NavigationLink { WorkoutHistoryView() } label: {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 20)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Workout history").accessibilityIdentifier("workout-history")
                        NavigationLink { WorkoutSettingsView() } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 20)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Workout settings").accessibilityIdentifier("workout-settings")
                    }.padding(.top, 12)

                    VStack(alignment: .leading, spacing: 13) {
                        Eyebrow(text: "A little time. A stronger you.")
                        Text("Your pace.\nYour practice.")
                            .font(.system(size: 49, weight: .semibold, design: .rounded)).tracking(-2.3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Make room for movement.")
                            .font(.system(.body, design: .rounded)).foregroundStyle(TempoTheme.muted)
                    }

                    HStack {
                        Text("Your routines").font(.system(.title3, design: .rounded, weight: .bold))
                        Text("\(store.routines.count)").font(.system(.caption, design: .monospaced, weight: .bold))
                            .padding(.horizontal, 9).padding(.vertical, 5).background(TempoTheme.line, in: Capsule())
                        Spacer()
                        Image(systemName: "square.stack.3d.up").foregroundStyle(TempoTheme.muted)
                    }.padding(.bottom, -12)

                    if store.routines.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "figure.cooldown").font(.system(size: 38))
                            Text("Start with a little movement.").font(.system(.title2, design: .rounded, weight: .semibold))
                            Text("Add your exercises and a moment to catch your breath. Your first routine starts here.")
                                .foregroundStyle(TempoTheme.muted)
                        }
                        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 26))
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(store.routines.enumerated()), id: \.element.id) { index, routine in
                                NavigationLink {
                                    RoutineDetailView(store: store, routineID: routine.id)
                                } label: {
                                    RoutineCard(routine: routine, featured: index == 0)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("routine-\(routine.name)")
                                .contextMenu {
                                    Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(routine) }
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "waveform").font(.system(size: 15))
                        Text("Less clock-watching. More moving.\nAudio cues guide every interval.")
                            .font(.system(.footnote, design: .rounded)).lineSpacing(3)
                    }
                    .foregroundStyle(TempoTheme.muted).padding(.horizontal, 6).padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
            .tempoBackground()
            .foregroundStyle(TempoTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Create routine", symbol: "plus") { showingEditor = true }
                    .accessibilityIdentifier("create-routine")
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 10)
                    .background(TempoTheme.paper)
            }
            .sheet(isPresented: $showingEditor) {
                RoutineEditorView(store: store, routine: Routine(name: "", steps: []), isNew: true)
            }
            .alert("Unable to save routines", isPresented: Binding(get: { store.errorMessage != nil && !showingEditor }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }
}

private struct RoutineCard: View {
    let routine: Routine
    let featured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                Image(systemName: routine.selectedIcon.symbol)
                    .font(.system(size: 27, weight: .medium))
                    .accessibilityLabel("\(routine.selectedIcon.title) routine icon")
                    .accessibilityIdentifier("routine-icon-\(routine.selectedIcon.rawValue)")
                    .frame(width: 58, height: 58)
                    .background(TempoTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                Spacer()
                Label(DurationText.short(routine.totalSeconds), systemImage: "timer")
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.white.opacity(0.5), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(routine.name).font(.system(.title2, design: .rounded, weight: .bold)).tracking(-0.7)
                Text("\(routine.exerciseCount) \(routine.exerciseCount == 1 ? "exercise" : "exercises")  ·  \(routine.steps.count - routine.exerciseCount) rest intervals")
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(TempoTheme.ink.opacity(0.7))
            }
            HStack(spacing: 5) {
                ForEach(routine.steps.prefix(18)) { step in
                    Capsule().fill(step.kind == .rest ? TempoTheme.ink.opacity(0.15) : TempoTheme.ink)
                        .frame(maxWidth: step.kind == .rest ? 9 : .infinity).frame(height: 5)
                }
                Spacer(minLength: 22)
                Image(systemName: "arrow.up.right").font(.system(size: 19, weight: .medium))
            }.accessibilityHidden(true)
        }
        .padding(24)
        .background(featured ? TempoTheme.lime : .white, in: RoundedRectangle(cornerRadius: 28))
        .foregroundStyle(TempoTheme.ink)
        .accessibilityElement(children: .combine)
    }
}

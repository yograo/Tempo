import SwiftUI

struct RoutineDetailView: View {
    @Bindable var store: RoutineStore
    let routineID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingDelete = false
    @State private var activeRoutine: Routine?

    private var routine: Routine? { store.routines.first { $0.id == routineID } }

    var body: some View {
        Group {
            if let routine {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack(spacing: 10) {
                                Image(systemName: routine.selectedIcon.symbol).font(.system(size: 23))
                                    .accessibilityLabel("\(routine.selectedIcon.title) routine icon")
                                Eyebrow(text: "Make this time yours")
                            }
                            Text(routine.name)
                                .font(.system(size: 40, weight: .semibold, design: .rounded)).tracking(-1.6)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("A little effort. A little rest. A fresh start.")
                                .font(.system(.subheadline, design: .rounded)).foregroundStyle(TempoTheme.muted)
                        }.padding(.top, 12)

                        HStack(spacing: 0) {
                            metric(DurationText.clock(routine.totalSeconds), label: "TOTAL TIME")
                            Rectangle().fill(TempoTheme.ink.opacity(0.13)).frame(width: 1, height: 38)
                            metric("\(routine.exerciseCount)", label: "EXERCISES")
                            Rectangle().fill(TempoTheme.ink.opacity(0.13)).frame(width: 1, height: 38)
                            metric(DurationText.short(routine.restSeconds), label: "REST TIME")
                        }
                        .padding(.vertical, 23).background(TempoTheme.lime, in: RoundedRectangle(cornerRadius: 24))

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("The lineup").font(.system(.title3, design: .rounded, weight: .bold))
                                Spacer()
                                Text("\(routine.steps.count) steps").font(.subheadline).foregroundStyle(TempoTheme.muted)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                                    StepRow(step: step, number: routine.steps.prefix(index + 1).filter { $0.kind == .exercise }.count)
                                    if index < routine.steps.count - 1 { Divider().overlay(TempoTheme.line).padding(.leading, 62) }
                                }
                            }.padding(.horizontal, 18).padding(.vertical, 8)
                                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                        }
                        Label("Beep between steps. A long tone at the finish.", systemImage: "speaker.wave.2")
                            .font(.footnote).foregroundStyle(TempoTheme.muted).padding(.bottom, 8)
                    }.padding(.horizontal, 24)
                }
                .safeAreaInset(edge: .bottom) {
                    PrimaryButton(title: "Start routine", symbol: "play.fill") { activeRoutine = routine }
                        .accessibilityIdentifier("start-routine")
                        .padding(.horizontal, 24).padding(.vertical, 12).background(TempoTheme.paper)
                }
                .sheet(isPresented: $showingEditor) { RoutineEditorView(store: store, routine: routine, isNew: false) }
            } else {
                ContentUnavailableView("Routine unavailable", systemImage: "timer")
            }
        }
        .tempoBackground().foregroundStyle(TempoTheme.ink)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Eyebrow(text: "Your routine", color: TempoTheme.ink) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit routine", systemImage: "pencil") { showingEditor = true }
                    Button("Duplicate routine", systemImage: "plus.square.on.square") { if let routine { store.duplicate(routine) } }
                    Button("Delete routine", systemImage: "trash", role: .destructive) { showingDelete = true }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .accessibilityLabel("Routine options")
            }
        }
        .confirmationDialog("Delete this routine?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete routine", role: .destructive) { if store.delete(routineID) { dismiss() } }
        } message: { Text("This will remove the routine and all of its steps.") }
        .fullScreenCover(item: $activeRoutine) { WorkoutView(routine: $0) }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 7) {
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.7)
        }.frame(maxWidth: .infinity)
    }
}

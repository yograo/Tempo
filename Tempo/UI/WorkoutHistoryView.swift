import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(WorkoutStore.self) private var workouts
    @State private var deleting: WorkoutRecord?

    private var records: [WorkoutRecord] { workouts.archive.records.sorted { $0.endedAt > $1.endedAt } }
    private var weekly: [WorkoutRecord] { workouts.archive.thisWeek() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Every little effort adds up")
                    Text("Your movement,\nremembered.")
                        .font(.system(size: 37, weight: .semibold, design: .rounded)).tracking(-1.3)
                    Text("Time spent moving and resting. Preparation and pauses don’t count.")
                        .font(.subheadline).foregroundStyle(TempoTheme.muted)
                }
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "This week")
                        Text("\(weekly.count)").font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(weekly.count == 1 ? "workout" : "workouts").font(.subheadline)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Eyebrow(text: "Workout time")
                        Text(DurationText.short(Int(weekly.reduce(0) { $0 + $1.activeSeconds }.rounded())))
                            .font(.system(size: 30, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                        Text("including rest").font(.subheadline)
                    }
                }.padding(24).background(TempoTheme.lime, in: RoundedRectangle(cornerRadius: 24))

                if let error = workouts.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Button("Retry saving") { workouts.retrySave() }
                    }.font(.subheadline).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                }

                if records.isEmpty {
                    ContentUnavailableView("Your first workout starts here", systemImage: "figure.cooldown",
                        description: Text("Finish a routine to see it here. Workouts you end early are saved too."))
                } else {
                    Text("Recent workouts").font(.system(.title3, design: .rounded, weight: .bold))
                    LazyVStack(spacing: 12) {
                        ForEach(records) { record in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: record.icon.symbol).font(.system(size: 24))
                                    .frame(width: 44, height: 48).background(TempoTheme.paper, in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(record.routineName).font(.system(.headline, design: .rounded))
                                    Text(record.endedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(TempoTheme.muted)
                                    Text("\(record.outcome == .finished ? "Finished" : "Ended early") · \(DurationText.short(record.durationSeconds))\(record.skippedSteps > 0 ? " · \(record.skippedSteps) skipped" : "")")
                                        .font(.caption).foregroundStyle(TempoTheme.muted)
                                }
                                Spacer(minLength: 0)
                                Menu {
                                    Button("Delete workout", systemImage: "trash", role: .destructive) { deleting = record }
                                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 44) }
                                    .accessibilityLabel("Options for \(record.routineName) workout")
                            }
                            .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("history-\(record.routineName)")
                        }
                    }
                }
            }.padding(24)
        }
        .tempoBackground().foregroundStyle(TempoTheme.ink)
        .navigationTitle("Workout history").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Delete this workout from history?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                if let deleting { workouts.delete(deleting.id) }
                deleting = nil
            }
        }
    }
}

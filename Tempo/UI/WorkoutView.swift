import SwiftUI

struct WorkoutView: View {
    @State private var controller: WorkoutController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingEnd = false

    init(routine: Routine) { _controller = State(initialValue: WorkoutController(routine: routine)) }

    private var timeline: WorkoutTimeline { controller.timeline }
    private var accent: Color { timeline.currentStep?.kind == .rest ? TempoTheme.mint : TempoTheme.lime }
    private var isComplete: Bool { timeline.state == .completed }
    private var status: String {
        if timeline.state == .paused { return "Paused" }
        if timeline.isPreparing { return "Get ready" }
        return timeline.currentStep?.kind == .rest ? "Breathe & recover" : "Time to move"
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if isComplete {
                        completion(wide: wide)
                            .frame(minHeight: wide ? max(220, geometry.size.height - 110) : nil)
                    } else {
                        let layout = wide ? AnyLayout(HStackLayout(spacing: 32)) : AnyLayout(VStackLayout(spacing: 24))
                        layout {
                            countdownPanel(fontSize: wide ? min(190, geometry.size.height * 0.53) : 100)
                                .frame(maxWidth: .infinity)
                            workoutControls
                                .frame(width: wide ? max(250, (geometry.size.width - 80) * 0.39) : nil)
                        }
                        .frame(minHeight: wide ? max(220, geometry.size.height - 110) : nil)
                    }
                    Text(controller.audioUnavailable ? "Sound is unavailable. Visual cues and haptics are still on." : controller.pausedAutomatically ? "Paused when you left the app. Resume when you’re ready." : "Keep Tempo open. Leaving the app pauses your timer.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(minHeight: geometry.size.height)
            }
        }
        .foregroundStyle(.white)
        .background(TempoTheme.dark.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .confirmationDialog("End this workout?", isPresented: $showingEnd, titleVisibility: .visible) {
            Button("End workout", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) { }
        } message: { Text("Your routine is saved. You can start it again any time.") }
        .task {
            TempoAppDelegate.setWorkoutOrientation(true)
            controller.start()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
                controller.tick()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.pauseForInterruption() }
            else { TempoAppDelegate.setWorkoutOrientation(true) }
        }
        .onDisappear {
            controller.stop()
            TempoAppDelegate.setWorkoutOrientation(false)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TempoMark(size: 25, color: TempoTheme.lime)
            Text("tempo").font(.system(size: 23, weight: .bold, design: .rounded)).tracking(-0.8)
            Label(timeline.routine.name, systemImage: timeline.routine.selectedIcon.symbol)
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                .lineLimit(1).padding(.leading, 12)
            Spacer(minLength: 8)
            Button { controller.toggleSound() } label: {
                Image(systemName: controller.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44).background(.white.opacity(0.08), in: Circle())
            }.accessibilityLabel(controller.soundEnabled ? "Mute sounds" : "Unmute sounds")
            Button {
                if isComplete { dismiss() }
                else {
                    if timeline.state == .running { controller.togglePause() }
                    showingEnd = true
                }
            } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44).background(.white.opacity(0.08), in: Circle())
            }.accessibilityLabel("Close workout")
        }
    }

    private func countdownPanel(fontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Eyebrow(text: status, color: accent)
            }
            Text(DurationText.clock(timeline.remainingSeconds))
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .monospacedDigit().tracking(-5)
                .minimumScaleFactor(0.4).lineLimit(1)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityIdentifier(timeline.isPreparing ? "preparation-countdown" : "countdown")
                .accessibilityLabel(DurationText.clock(timeline.remainingSeconds))
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(accent).frame(width: geometry.size.width * max(0, 1 - timeline.stepProgress))
                }
            }.frame(height: 7).accessibilityHidden(true)
            HStack {
                Text(timeline.isPreparing ? "STARTING IN" : "STEP \(timeline.stepIndex + 1) OF \(timeline.routine.steps.count)")
                Spacer()
                Text("\(DurationText.clock(timeline.totalRemaining)) LEFT")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var workoutControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: timeline.isPreparing ? timeline.routine.selectedIcon.symbol : (timeline.currentStep?.symbol ?? "timer"))
                        .font(.system(size: 23)).foregroundStyle(accent)
                    Eyebrow(text: timeline.isPreparing ? "Make this time yours" : (timeline.currentStep?.kind.title ?? "Exercise"), color: accent)
                }
                Text(timeline.isPreparing ? "Get ready." : (timeline.currentStep?.displayName ?? ""))
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.8)
                    .lineLimit(2).minimumScaleFactor(0.65)
                    .accessibilityIdentifier(timeline.isPreparing ? "preparation-title" : "current-step")
            }
            HStack(spacing: 10) {
                Image(systemName: nextStep?.symbol ?? "checkmark").foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: timeline.isPreparing ? "First up" : nextStep == nil ? "The finish line" : "Up next", color: .white.opacity(0.5))
                    Text(nextStep?.displayName ?? "Routine complete")
                        .font(.system(.subheadline, design: .rounded, weight: .medium)).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let nextStep {
                    Text(DurationText.clock(nextStep.seconds))
                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(14).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))

            HStack(spacing: 10) {
                PrimaryButton(title: timeline.state == .paused ? "Resume" : "Pause", symbol: timeline.state == .paused ? "play.fill" : "pause.fill", color: accent, foreground: TempoTheme.dark) {
                    controller.togglePause()
                }.accessibilityIdentifier("pause-resume")
                Button { controller.skip() } label: {
                    Image(systemName: timeline.isPreparing ? "play.fill" : "forward.end.fill")
                        .font(.system(size: 20)).frame(width: 60, height: 60)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                }
                .accessibilityLabel(timeline.isPreparing ? "Start now" : "Skip step")
                .accessibilityIdentifier(timeline.isPreparing ? "skip-preparation" : "skip-step")
            }
        }
    }

    private var nextStep: RoutineStep? {
        let next = timeline.isPreparing ? 0 : timeline.stepIndex + 1
        return timeline.routine.steps.indices.contains(next) ? timeline.routine.steps[next] : nil
    }

    private func completion(wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(spacing: 40)) : AnyLayout(VStackLayout(spacing: 24))
        return layout {
            ZStack {
                Circle().stroke(TempoTheme.lime.opacity(0.15), lineWidth: 1)
                Circle().fill(TempoTheme.lime).padding(22)
                Image(systemName: "checkmark").font(.system(size: 65, weight: .light)).foregroundStyle(TempoTheme.dark)
            }.frame(width: 190, height: 190)
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Routine complete", color: TempoTheme.lime)
                Text("You showed up.")
                    .font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-1.4)
                Text("Take a breath. Take that feeling with you.")
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 18) {
                    PrimaryButton(title: "Back to routine", symbol: "checkmark", color: TempoTheme.lime, foreground: TempoTheme.dark) { dismiss() }
                        .accessibilityIdentifier("finish-workout")
                    Button("Go again") { controller.restart() }
                        .font(.system(.body, design: .rounded, weight: .semibold)).fixedSize()
                        .accessibilityIdentifier("restart-workout")
                }.padding(.top, 6)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

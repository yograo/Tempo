import SwiftUI

struct RoutineEditorView: View {
    @Bindable var store: RoutineStore
    @State var routine: Routine
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var editingStep: RoutineStep?
    @State private var showDiscard = false
    @State private var original: Routine?
    @State private var editMode: EditMode = .inactive
    @State private var rememberedDurations: [StepKind: Int] = [:]
    @FocusState private var routineNameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("e.g. Morning movement", text: $routine.name)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .accessibilityLabel("Routine name").accessibilityIdentifier("routine-name")
                        .focused($routineNameFocused).submitLabel(.done)
                        .onSubmit { routineNameFocused = false }
                        .padding(.vertical, 9)
                    NavigationLink {
                        ExerciseIconPicker(selection: $routine.selectedIcon)
                    } label: {
                        IconChoiceRow(title: "Routine icon", icon: routine.selectedIcon)
                    }.accessibilityIdentifier("choose-routine-icon")
                } header: { Eyebrow(text: "Routine name") }

                Section {
                    if routine.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "list.bullet.clipboard").font(.system(size: 26)).padding(.bottom, 4)
                            Text("Build your flow").font(.system(.headline, design: .rounded))
                            Text("Add an exercise, set its time, then add a rest wherever you need one.")
                                .font(.subheadline).foregroundStyle(TempoTheme.muted)
                        }.padding(.vertical, 20)
                    }
                    ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                        Button { editingStep = step } label: {
                            StepRow(step: step, number: routine.steps.prefix(index + 1).filter { $0.kind == .exercise }.count)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Edit \(step.displayName), \(step.seconds) seconds")
                    }
                    .onDelete { routine.steps.remove(atOffsets: $0) }
                    .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    HStack {
                        Eyebrow(text: "Your steps")
                        Spacer()
                        Text(DurationText.short(routine.totalSeconds)).font(.system(.caption, design: .monospaced))
                    }
                } footer: {
                    if !routine.steps.isEmpty { Text("Tap a step to edit it. Swipe to delete, or use Reorder to change the sequence.") }
                }

                Section {
                    Button {
                        routineNameFocused = false
                        editingStep = RoutineStep(kind: .exercise, name: "", seconds: defaultDuration(for: .exercise))
                    } label: { Label("Add exercise", systemImage: "plus.circle.fill").fontWeight(.semibold).padding(.vertical, 6) }
                        .accessibilityIdentifier("add-exercise")
                    Button {
                        routineNameFocused = false
                        editingStep = RoutineStep(kind: .rest, name: "Rest", seconds: defaultDuration(for: .rest))
                    } label: { Label("Add rest interval", systemImage: "wind").fontWeight(.semibold).padding(.vertical, 6) }
                        .accessibilityIdentifier("add-rest")
                }
                if routine.exerciseCount == 0 {
                    Text("Include at least one exercise to save your routine.")
                        .font(.footnote).foregroundStyle(TempoTheme.muted).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively).tempoBackground()
            .navigationTitle(isNew ? "New routine" : "Edit routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if routine != original { showDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }.accessibilityLabel("Reorder steps").disabled(routine.steps.count < 2)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save routine", symbol: "checkmark") { if store.save(routine) { dismiss() } }
                    .disabled(!routine.isValid).opacity(routine.isValid ? 1 : 0.4)
                    .accessibilityIdentifier("save-routine")
                    .padding(.horizontal, 24).padding(.vertical, 12).background(TempoTheme.paper)
            }
            .sheet(item: $editingStep) { step in
                StepEditorView(step: step) { updated in
                    if let index = routine.steps.firstIndex(where: { $0.id == updated.id }) { routine.steps[index] = updated }
                    else { routine.steps.append(updated) }
                    rememberedDurations[updated.kind] = updated.seconds
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .alert("Unable to save routine", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
            .onAppear { if original == nil { original = routine } }
            .environment(\.editMode, $editMode)
            .interactiveDismissDisabled(routine != original)
        }
    }

    private func defaultDuration(for kind: StepKind) -> Int {
        rememberedDurations[kind]
            ?? routine.steps.last(where: { $0.kind == kind })?.seconds
            ?? (kind == .exercise ? 30 : 15)
    }
}

private struct StepEditorView: View {
    @State var step: RoutineStep
    let onSave: (RoutineStep) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(step.kind == .rest ? "Rest" : "e.g. Jumping jacks", text: $step.name)
                        .accessibilityLabel("Step name").accessibilityIdentifier("step-name")
                        .focused($nameFocused)
                    if step.kind == .exercise {
                        NavigationLink {
                            ExerciseIconPicker(selection: $step.selectedIcon)
                        } label: {
                            IconChoiceRow(title: "Exercise icon", icon: step.selectedIcon)
                        }.accessibilityIdentifier("choose-exercise-icon")
                    }
                }
                Section {
                    HStack(spacing: 0) {
                        Picker("Minutes", selection: Binding(get: { step.seconds / 60 }, set: { step.seconds = $0 * 60 + step.seconds % 60 })) {
                            ForEach(0..<60) { Text("\($0) min").tag($0) }
                        }
                        .pickerStyle(.wheel).accessibilityIdentifier("minutes-picker")
                        Picker("Seconds", selection: Binding(get: { step.seconds % 60 }, set: { step.seconds = (step.seconds / 60) * 60 + $0 })) {
                            ForEach(0..<60) { Text("\($0) sec").tag($0) }
                        }
                        .pickerStyle(.wheel).accessibilityIdentifier("seconds-picker")
                    }
                    HStack(spacing: 8) {
                        ForEach([15, 30, 45, 60], id: \.self) { seconds in
                            Button(DurationText.short(seconds)) { step.seconds = seconds; nameFocused = false }
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(step.seconds == seconds ? TempoTheme.lime : TempoTheme.paper, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }.padding(.vertical, 6)
                } header: { Text("Duration") } footer: { Text("Choose between 1 second and 59 minutes, 59 seconds.") }
            }
            .scrollContentBackground(.hidden).tempoBackground()
            .navigationTitle(step.kind == .rest ? "Rest interval" : "Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("cancel-step")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(step); dismiss() }.fontWeight(.semibold).disabled(!step.isValid)
                        .accessibilityIdentifier("save-step")
                }
            }
        }
    }
}

import SwiftUI

struct SettingsActivityRulesView: View {
    @ObservedObject var manager = ActivityRulesManager.shared
    @State private var showingAddRule = false
    @State private var ruleToEdit: ActivityRule?
    @State private var selectedTab = 0
    @State private var newRule = ActivityRule(name: "New Rule", resultingActivityType: "walking", conditions: [])
    
    var body: some View {
        VStack {
            Picker("Mode", selection: $selectedTab) {
                Text("Splitting").tag(0)
                Text("Categorization").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            if selectedTab == 0 {
                List {
                    Section(header: Text("Built-in Workout Splitting")) {
                        NavigationLink(destination: EditSplitRuleView(rule: $manager.workoutSplitRule)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Split by workout activities").font(.headline)
                                    Text("Min points: \(manager.workoutSplitRule.minimumPoints)").font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $manager.workoutSplitRule.isActive)
                                    .labelsHidden()
                            }
                        }
                    }
                    
                    Section(
                        header: Text("Rules are evaluated in order. Drag to reorder."),
                        footer: Text("These rules are used to split tracks into smaller segments based on activity.")
                    ) {
                        ForEach($manager.splitRules) { $rule in
                            NavigationLink(destination: EditSplitRuleView(rule: $rule)) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(rule.activityType.capitalized).font(.headline)
                                        if rule.activityType != "unknown" {
                                            Text("Min split: \(rule.minimumPoints), stop: \(rule.minimumPointsToStop) (\(rule.minimumConfidence))").font(.subheadline).foregroundColor(.secondary)
                                        } else {
                                            Text("Min split: \(rule.minimumPoints), stop: \(rule.minimumPointsToStop)").font(.subheadline).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: $rule.isActive)
                                        .labelsHidden()
                                }
                            }
                        }
                        .onMove(perform: moveSplitRules)
                    }
                }
            } else {
                List {
                    Section(
                        header: Text("Rules are evaluated in order. Drag to reorder."),
                        footer: Text("These rules are evaluated when a track has been finalized, to further improve the quality of the result. If no rules match, the default categorization will be kept.")
                    ) {
                        ForEach($manager.rules) { $rule in
                            NavigationLink(destination: EditActivityRuleView(rule: $rule, isNew: false) { updatedRule in
                                if let index = manager.rules.firstIndex(where: { $0.id == updatedRule.id }) {
                                    manager.rules[index] = updatedRule
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(rule.name).font(.headline)
                                        Text("Result: \(rule.resultingActivityType)").font(.subheadline).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $rule.isActive)
                                        .labelsHidden()
                                }
                            }
                        }
                        .onMove(perform: moveRules)
                        .onDelete(perform: deleteRules)
                    }
                }
            }
        }
        .navigationTitle("Activity Rules")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == 1 {
                    Button(action: { showingAddRule = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddRule, onDismiss: {
            newRule = ActivityRule(name: "New Rule", resultingActivityType: "walking", conditions: [])
        }) {
            NavigationView {
                EditActivityRuleView(rule: $newRule, isNew: true) { addedRule in
                    manager.rules.append(addedRule)
                    showingAddRule = false
                }
                .navigationBarItems(leading: Button("Cancel") {
                    showingAddRule = false
                })
            }
        }
    }
    
    private func moveRules(from source: IndexSet, to destination: Int) {
        manager.rules.move(fromOffsets: source, toOffset: destination)
    }
    
    private func moveSplitRules(from source: IndexSet, to destination: Int) {
        manager.splitRules.move(fromOffsets: source, toOffset: destination)
    }
    
    private func deleteRules(at offsets: IndexSet) {
        manager.rules.remove(atOffsets: offsets)
    }
}

struct EditSplitRuleView: View {
    @Binding var rule: SplitRule
    
    let confidenceOptions = ["High", "Medium", "Low"]
    let allowedPoints = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50]
    
    private var splitPointIndex: Binding<Double> {
        Binding(
            get: {
                if let index = allowedPoints.firstIndex(of: rule.minimumPoints) {
                    return Double(index)
                }
                return 0
            },
            set: { newValue in
                let index = Int(newValue)
                if index >= 0 && index < allowedPoints.count {
                    rule.minimumPoints = allowedPoints[index]
                }
            }
        )
    }
    
    private var stopPointIndex: Binding<Double> {
        Binding(
            get: {
                if let index = allowedPoints.firstIndex(of: rule.minimumPointsToStop) {
                    return Double(index)
                }
                return 0
            },
            set: { newValue in
                let index = Int(newValue)
                if index >= 0 && index < allowedPoints.count {
                    rule.minimumPointsToStop = allowedPoints[index]
                }
            }
        )
    }
    
    var body: some View {
        Form {
            Section(header: Text("Rule Settings")) {
                Toggle("Active", isOn: $rule.isActive)
                
                HStack {
                    Text("Activity Type")
                    Spacer()
                    Text(rule.activityType.capitalized)
                        .foregroundColor(.secondary)
                }
                
                if rule.activityType != "unknown" {
                    Picker("Minimum Confidence", selection: $rule.minimumConfidence) {
                        ForEach(confidenceOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum Points to Split: \(rule.minimumPoints)")
                        .font(.headline)
                    Text("At least this many points are needed for a new track of this type to be started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(
                        value: splitPointIndex,
                        in: 0...Double(allowedPoints.count - 1),
                        step: 1
                    )
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum Points to Stop: \(rule.minimumPointsToStop)")
                        .font(.headline)
                    Text("At least this many points of different type are needed to stop this track type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(
                        value: stopPointIndex,
                        in: 0...Double(allowedPoints.count - 1),
                        step: 1
                    )
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Edit Split Rule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Alias for backward compatibility
typealias ActivityRulesListView = SettingsActivityRulesView

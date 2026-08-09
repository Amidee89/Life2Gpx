import SwiftUI

struct EditActivityRuleView: View {
    @Binding var rule: ActivityRule
    var isNew: Bool
    var onSave: (ActivityRule) -> Void
    
    @State private var localRule: ActivityRule
    @State private var showingAddCondition = false
    @State private var draftCondition = RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "")
    @ObservedObject var prefs = PreferencesManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    init(rule: Binding<ActivityRule>, isNew: Bool, onSave: @escaping (ActivityRule) -> Void) {
        self._rule = rule
        self.isNew = isNew
        self.onSave = onSave
        self._localRule = State(initialValue: rule.wrappedValue)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Rule Info")) {
                TextField("Rule Name", text: $localRule.name)
                
                NavigationLink {
                    TrackTypePickerView(selectedId: $localRule.resultingActivityType)
                } label: {
                    HStack {
                        Text("Resulting Track Type")
                        Spacer()
                        if let currentType = prefs.trackType(for: localRule.resultingActivityType) {
                            PlaceIconView(icon: currentType.icon, fallbackColor: currentType.color)
                                .frame(width: 20)
                            Text(currentType.name)
                                .foregroundColor(.secondary)
                        } else {
                            Text(localRule.resultingActivityType)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section(header: Text("Conditions")) {
                ForEach(localRule.conditions.indices, id: \.self) { index in
                    NavigationLink(destination: EditConditionView(condition: $localRule.conditions[index], isFirst: index == 0, onSave: nil)) {
                        VStack(alignment: .leading, spacing: 4) {
                            if index > 0 {
                                Text(localRule.conditions[index].logicalOperator.rawValue)
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.blue)
                            }
                            
                            let condition = localRule.conditions[index]
                            Text(condition.conditionType.rawValue)
                                .font(.subheadline)
                            
                            HStack {
                                if condition.conditionType == .startingPlace || condition.conditionType == .endingPlace {
                                    Text("Place: \(condition.value1)")
                                } else if condition.conditionType == .iosActivityType {
                                    Text("\(condition.value2 ?? "0")% \(condition.value1)")
                                } else if condition.conditionType == .distanceFromPlace {
                                    let op = condition.comparisonOperator?.rawValue ?? ""
                                    if condition.comparisonOperator == .between {
                                        Text("\(condition.value2 ?? "0")% are \(op) \(condition.value3 ?? "0")-\(condition.value4 ?? "0")m from \(condition.value1)")
                                    } else {
                                        Text("\(condition.value2 ?? "0")% are \(op) \(condition.value3 ?? "0")m from \(condition.value1)")
                                    }
                                } else {
                                    let op = condition.comparisonOperator?.rawValue ?? ""
                                    if condition.comparisonOperator == .between {
                                        Text("\(op) \(condition.value1) and \(condition.value2 ?? "")")
                                    } else {
                                        Text("\(op) \(condition.value1)")
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    localRule.conditions.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    localRule.conditions.move(fromOffsets: source, toOffset: destination)
                }
                
                Button(action: { showingAddCondition = true }) {
                    Text("Add Condition")
                }
            }
        }
        .navigationTitle(isNew ? "New Rule" : "Edit Rule")
        .toolbar {
            if !isNew {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    onSave(localRule)
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .sheet(isPresented: $showingAddCondition) {
            NavigationView {
                EditConditionView(condition: $draftCondition, isFirst: localRule.conditions.isEmpty) { condition in
                    localRule.conditions.append(condition)
                    showingAddCondition = false
                    draftCondition = RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "")
                }
                .navigationBarItems(leading: Button("Cancel") {
                    showingAddCondition = false
                    draftCondition = RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "")
                })
            }
        }
    }
}

struct EditConditionView: View {
    @Binding var condition: RuleCondition
    var isFirst: Bool
    var onSave: ((RuleCondition) -> Void)?
    @FocusState private var fieldIsFocused: Bool
    
    var body: some View {
        Form {
            if !isFirst {
                Section(header: Text("Logical Operator")) {
                    Picker("Operator", selection: $condition.logicalOperator) {
                        ForEach(LogicalOperator.allCases) { op in
                            Text(op.rawValue).tag(op)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            Section(header: Text("Condition Type")) {
                Picker("Type", selection: $condition.conditionType) {
                    ForEach(RuleConditionType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }
            
            if condition.conditionType == .speed || condition.conditionType == .elevation {
                Section(header: Text("Calculation Method")) {
                    Picker("Type", selection: $condition.speedCalculationType) {
                        Text("Average").tag(SpeedCalculationType.average as SpeedCalculationType?)
                        Text("Median").tag(SpeedCalculationType.median as SpeedCalculationType?)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            if condition.conditionType.requiresComparison {
                Section(header: Text("Comparison")) {
                    Picker("Operator", selection: Binding(
                        get: { condition.comparisonOperator ?? .lessThan },
                        set: { condition.comparisonOperator = $0 }
                    )) {
                        ForEach(ComparisonOperator.allCases) { op in
                            Text(op.rawValue).tag(op)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            Section(header: Text("Values")) {
                if condition.conditionType == .startingPlace || condition.conditionType == .endingPlace {
                    TextField("Place ID", text: $condition.value1)
                        .focused($fieldIsFocused)
                } else if condition.conditionType == .iosActivityType {
                    TextField("iOS Activity Type (e.g. walking)", text: $condition.value1)
                        .autocapitalization(.none)
                        .focused($fieldIsFocused)
                    TextField("Percentage (0-100)", text: Binding(
                        get: { condition.value2 ?? "" },
                        set: { condition.value2 = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .focused($fieldIsFocused)
                } else if condition.conditionType == .distanceFromPlace {
                    TextField("Place ID", text: $condition.value1)
                        .focused($fieldIsFocused)
                    TextField("Distance (meters)", text: Binding(
                        get: { condition.value3 ?? "" },
                        set: { condition.value3 = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .focused($fieldIsFocused)
                    
                    if condition.comparisonOperator == .between {
                        TextField("Max Distance (meters)", text: Binding(
                            get: { condition.value4 ?? "" },
                            set: { condition.value4 = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .focused($fieldIsFocused)
                    }
                    
                    TextField("Required Percentage (0-100)", text: Binding(
                        get: { condition.value2 ?? "" },
                        set: { condition.value2 = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .focused($fieldIsFocused)
                } else {
                    TextField("Value", text: $condition.value1)
                        .keyboardType(.decimalPad)
                        .focused($fieldIsFocused)
                    
                    if condition.comparisonOperator == .between {
                        TextField("Max Value", text: Binding(
                            get: { condition.value2 ?? "" },
                            set: { condition.value2 = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .focused($fieldIsFocused)
                    }
                }
            }
        }
        .navigationTitle(onSave == nil ? "Edit Condition" : "New Condition")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldIsFocused = false }
            }
            if let onSave = onSave {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onSave(condition)
                    }
                }
            }
        }
    }
}

import SwiftUI

struct ActivityRulesListView: View {
    @ObservedObject var manager = ActivityRulesManager.shared
    @State private var showingAddRule = false
    @State private var ruleToEdit: ActivityRule?
    
    var body: some View {
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
        .navigationTitle("Activity Rules")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddRule = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRule) {
            let newRule = ActivityRule(name: "New Rule", resultingActivityType: "walking", conditions: [])
            NavigationView {
                EditActivityRuleView(rule: .constant(newRule), isNew: true) { addedRule in
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
    
    private func deleteRules(at offsets: IndexSet) {
        manager.rules.remove(atOffsets: offsets)
    }
}

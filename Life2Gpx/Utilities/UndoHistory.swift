import Foundation

public struct UndoHistory<T> {
    public var undoStack: [T] = []
    public var redoStack: [T] = []
    
    public init() {}
    
    public var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    public var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    public mutating func push(currentState: T) {
        undoStack.append(currentState)
        redoStack.removeAll()
    }
    
    public mutating func undo(currentState: T) -> T? {
        guard let previousState = undoStack.popLast() else { return nil }
        redoStack.append(currentState)
        return previousState
    }
    
    public mutating func redo(currentState: T) -> T? {
        guard let nextState = redoStack.popLast() else { return nil }
        undoStack.append(currentState)
        return nextState
    }
    
    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

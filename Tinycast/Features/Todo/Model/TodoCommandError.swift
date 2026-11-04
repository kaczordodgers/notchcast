import Foundation

enum TodoCommandError: Error, Equatable, Sendable {
    case unknownID(TodoCommand.Entity, String)
    case duplicateID(String)
    case invalidID(String)
    case invalidPriority(Int)
    case parentCycle(String)
    case sectionProjectMismatch(String)
    case parentLocationMismatch(String)
    case duplicateLabel(String)
    case invalidDue(String)
}

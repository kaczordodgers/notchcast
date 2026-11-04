import Foundation

nonisolated enum KatanaMkIIBlock: String, CaseIterable, Sendable {
    case name = "PatchName", patch0 = "Patch_0", eq2 = "Eq(2)", fx1 = "Fx(1)", fx2 = "Fx(2)"
    case delay1 = "Delay(1)", delay2 = "Delay(2)", patch1 = "Patch_1", patch2 = "Patch_2", status = "Status"
    case knobAssign = "KnobAsgn", pedalAssign = "ExpPedalAsgn", pedalRange = "ExpPedalAsgnMinMax", fsAssign = "FsAsgn"
    case solo = "Patch_Mk2V2", contour1 = "Contour(1)", contour2 = "Contour(2)", contour3 = "Contour(3)"

    var key: String { "UserPatch%\(rawValue)" }

    var size: Int {
        switch self {
        case .name: 16
        case .patch0: 72
        case .eq2: 24
        case .fx1, .fx2: 225
        case .delay1, .delay2: 26
        case .patch1: 91
        case .patch2: 36
        case .status: 18
        case .knobAssign, .pedalAssign: 34
        case .pedalRange: 78
        case .fsAssign, .contour1, .contour2, .contour3: 2
        case .solo: 22
        }
    }

    var fileOffset: Int {
        switch self {
        case .name: 0
        case .patch0: 16
        case .eq2: 96
        case .fx1: 128
        case .fx2: 384
        case .delay1: 640
        case .delay2: 672
        case .patch1: 704
        case .patch2: 800
        case .status: 848
        case .knobAssign: 896
        case .pedalAssign: 1024
        case .pedalRange: 1072
        case .fsAssign: 1928
        case .solo: 1936
        case .contour1: 1968
        case .contour2: 1976
        case .contour3: 1984
        }
    }
}

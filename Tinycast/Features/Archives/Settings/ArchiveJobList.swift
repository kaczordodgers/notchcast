import SwiftUI

struct ArchiveJobList: View {
    let module: ArchiveModule

    var body: some View {
        ForEach(module.queue.jobs) { job in
            ArchiveJobRow(job: job, module: module)
        }
    }
}

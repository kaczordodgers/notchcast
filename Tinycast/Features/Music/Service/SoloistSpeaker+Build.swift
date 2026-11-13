import Foundation

extension SoloistSpeaker {
    func installBuild() {
        guard installing == nil else { return }
        cancelWork()
        installFailure = nil
        state = .downloading
        let token = generation
        let builds = builds
        installing = Task { [weak self] in
            do {
                let build = try await builds.install()
                guard !Task.isCancelled, let self, token == self.generation else { return false }
                self.installing = nil
                self.rejectedBuilds.remove(build.executable)
                self.build = build
                if self.enabled {
                    self.stopChild()
                    self.begin()
                } else { self.state = .off }
                return true
            } catch {
                guard !Task.isCancelled, let self, token == self.generation else { return false }
                self.installing = nil
                self.installFailure = (error as? SoloistFailure) ?? .download
                if self.child != nil {
                    self.state = .starting
                    self.checkPort(until: self.schedule.now() + 10)
                } else if self.enabled { self.begin() } else { self.state = .off }
                return false
            }
        }
    }

    func refreshInstalledBuild() async {
        let token = generation
        do {
            let installed = try await builds.installed(excluding: rejectedBuilds)
            guard !Task.isCancelled, token == generation, installing == nil else { return }
            build = installed
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, token == generation, installing == nil else { return }
            installFailure = (error as? SoloistFailure) ?? .filesystem
        }
    }
}

import Foundation
import Observation

/// Holds the Remote dashboard's widget order/visibility and keeps the
/// dashboard and Customize screen in sync, mirroring how `QuickPokeService`
/// shares its settings.
@MainActor
@Observable
final class RemoteDashboardLayoutService {
    private let store: RemoteDashboardLayoutStore

    private(set) var layout: RemoteDashboardLayout

    init(store: RemoteDashboardLayoutStore = RemoteDashboardLayoutStore()) {
        self.store = store
        self.layout = store.load()
    }

    func move(_ kind: RemoteWidgetKind, by offset: Int) {
        layout.move(kind, by: offset)
        store.save(layout)
    }

    func hide(_ kind: RemoteWidgetKind) {
        layout.hide(kind)
        store.save(layout)
    }

    func show(_ kind: RemoteWidgetKind) {
        layout.show(kind)
        store.save(layout)
    }
}

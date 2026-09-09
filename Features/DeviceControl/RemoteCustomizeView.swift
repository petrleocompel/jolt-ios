import SwiftUI

/// Reorder, hide, and re-add Remote dashboard widgets. Device status isn't
/// one of these — it's pinned first on the dashboard unconditionally, so
/// there's nothing to manage for it here.
struct RemoteCustomizeView: View {
    let layoutService: RemoteDashboardLayoutService
    var isQuickPokeConfigured: Bool

    @Environment(\.dismiss) private var dismiss

    private var layout: RemoteDashboardLayout { layoutService.layout }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(layout.visible.enumerated()), id: \.element) { index, kind in
                        activeRow(kind, index: index)
                    }
                } header: {
                    Text("On your home screen")
                } footer: {
                    Text("Use the arrows to reorder, or remove a widget to send it to the gallery below.")
                }

                Section {
                    if layout.hidden.isEmpty {
                        Text("Every widget is already on your home screen.")
                            .foregroundStyle(.secondary)
                    } else {
                        galleryGrid
                    }
                } header: {
                    Text("Widget gallery")
                } footer: {
                    if !isQuickPokeConfigured && (layout.visible.contains(.quickPoke) || layout.hidden.contains(.quickPoke)) {
                        Text("Quick poke only appears on your dashboard once it's configured in Settings → Quick poke.")
                    }
                }
            }
            .navigationTitle("Customize home")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func activeRow(_ kind: RemoteWidgetKind, index: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).font(.body)
                Text(kind.hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                layoutService.move(kind, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .accessibilityLabel("Move \(kind.displayName) up")

            Button {
                layoutService.move(kind, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == layout.visible.count - 1)
            .accessibilityLabel("Move \(kind.displayName) down")

            Button(role: .destructive) {
                layoutService.hide(kind)
            } label: {
                Image(systemName: "minus.circle")
            }
            .accessibilityLabel("Remove \(kind.displayName) from home screen")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("customizeRow_\(kind.rawValue)")
    }

    private var galleryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(layout.hidden) { kind in
                Button {
                    layoutService.show(kind)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                        }
                        Text(kind.displayName).font(.subheadline.weight(.medium))
                        Text(kind.hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("galleryAdd_\(kind.rawValue)")
            }
        }
        .listRowInsets(EdgeInsets())
        .padding(.vertical, 4)
    }
}

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: DeviceStore
    @ObservedObject var discovery: DeviceDiscovery
    var onScan: () -> Void
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MES AFFICHEURS")
                        .font(.caption2.weight(.semibold)).tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6).padding(.bottom, 2)

                    ForEach(store.devices) { device in
                        DeviceRow(device: device, isSelected: store.selectedID == device.id)
                            .contentShape(Rectangle())
                            .onTapGesture { store.selectedID = device.id }
                            .contextMenu {
                                Button("Oublier ce device", role: .destructive) {
                                    store.remove(device)
                                }
                            }

                        // Sous-sections de l'appareil sélectionné.
                        if store.selectedID == device.id {
                            VStack(spacing: 2) {
                                ForEach(DeviceSection.allCases) { section in
                                    SectionRow(section: section,
                                               isSelected: store.selectedSection == section)
                                        .contentShape(Rectangle())
                                        .onTapGesture { store.selectedSection = section }
                                }
                            }
                            .padding(.leading, 18)
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.selectedID)
            }

            Spacer(minLength: 0)
            footer
        }
        .background(VisualEffectView(material: .sidebar))
        .sheet(isPresented: $showAddSheet) { AddDeviceSheet() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.accentGradient)
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "rays").font(.system(size: 13, weight: .bold)).foregroundStyle(.black.opacity(0.8)))
                .shadow(color: Theme.accent.opacity(0.4), radius: 6, y: 2)
            Text("Lumo")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if discovery.isScanning {
                HStack(spacing: 8) {
                    ProgressView(value: discovery.progress).tint(Theme.accent)
                    Text("\(Int(discovery.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 8) {
                Button(action: onScan) {
                    Label(discovery.isScanning ? "Recherche…" : "Rechercher",
                          systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(discovery.isScanning)

                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
        .padding(14)
    }
}

private struct DeviceRow: View {
    let device: Device
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                    .frame(width: 30, height: 30)
                Image(systemName: "display")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .black.opacity(0.8) : Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(device.host)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.white.opacity(0.05) : .clear)
        )
    }
}

private struct SectionRow: View {
    let section: DeviceSection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                .frame(width: 18)
            Text(section.title)
                .font(.callout)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Theme.accent.opacity(0.14) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.22) : .clear, lineWidth: 1)
        )
    }
}

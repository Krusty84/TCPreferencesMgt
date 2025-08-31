//
//  CompareWindowView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 30/08/2025.
//

import SwiftUI
import SwiftData
import TCSwiftBridge

struct CompareWindowView: View {
    let payload: CompareLaunchPayload
    @Environment(\.modelContext) private var context

    // ViewModel with new names
    @StateObject private var vm: CompareWindowViewModel

    // UI-only
    @State private var nameFilter: String = ""
    @State private var showOnlyDiffs = true
    @State private var nameColWidth: CGFloat = 260
    @State private var catColWidth:  CGFloat = 160
    private let valColWidth: CGFloat = 280
    private let indColWidth: CGFloat = 26
    private let edgeGutter: CGFloat = 6
    private let rowHSpacing: CGFloat = 3
    private let cellHPad: CGFloat = 4
    private let cellVPad: CGFloat = 3

    init(payload: CompareLaunchPayload) {
        self.payload = payload
        _vm = StateObject(wrappedValue: CompareWindowViewModel(payload: payload))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            comparingTable.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(.horizontal, edgeGutter)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .padding(.horizontal, edgeGutter)
        .frame(minWidth: 1000, minHeight: 560)
        .onAppear { vm.setContext(context) }
        .task { await vm.initialLoad() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            TextField("Search by name, category, or values among the loaded", text: $nameFilter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
            Spacer()
            Toggle("Show only differences", isOn: $showOnlyDiffs)
                .toggleStyle(.switch)
                .disabled(vm.isBusy)

            Divider().frame(height: 22)

            Button {
                Task { await vm.refreshPrimary() }
            } label: {
                HStack(spacing: 6) {
                    if vm.isRefreshingPrimary { ProgressView().controlSize(.small) }
                    Text("Update Primary")
                }
            }
            .buttonStyle(.bordered)
            .disabled(vm.isBusy)

            Button {
                Task { await vm.refreshAllSecondary() }
            } label: {
                HStack(spacing: 6) {
                    if vm.isRefreshingAllSecondary { ProgressView().controlSize(.small) }
                    Text("Update All Secondary")
                }
            }
            .buttonStyle(.bordered)
            .disabled(vm.isBusy || vm.secondaryConnections.isEmpty)
        }
        .padding(.horizontal, edgeGutter)
        .padding(.vertical, 8)
        .background(.bar)
    }
    
    @ViewBuilder
    private func headerStatusIcon(isUpdating: Bool, isFresh: Bool, error: String?) -> some View {
        if isUpdating {
            ProgressView().controlSize(.small).scaleEffect(0.75)
        } else if error != nil {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if isFresh {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            EmptyView()
        }
    }

    // MARK: Table

    private var comparingTable: some View {
        let allNames  = Array(Set(payload.preferenceNames)).sorted { $0.localizedCompare($1) == .orderedAscending }
        let filtered  = allNames.filter { vm.matchesSearch(name: $0, filter: nameFilter) }
        let shownNames = showOnlyDiffs ? filtered.filter { vm.rowHasAnyDiff(name: $0) } : filtered

        return HStack(spacing: 0) {
            primaryConnectionPane(shownNames: shownNames)
            separator
            secondaryConnectionsPane(shownNames: shownNames)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    
    

    // MARK: Left Pane

    @ViewBuilder
    private func primaryConnectionPane(shownNames: [String]) -> some View {
        VStack(spacing: 0) {
            leftHeader
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(shownNames.enumerated()), id: \.offset) { (rowIndex, n) in
                        leftRow(rowIndex: rowIndex, name: n)
                    }
                }
            }
        }
    }

    private var leftHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: rowHSpacing) {
            Text("Name").font(.headline)
                .measureNameWidth { nameColWidth = max(nameColWidth, $0) }
                .frame(width: nameColWidth, alignment: .leading)

            Text("Category").font(.headline)
                .measureCategoryWidth { catColWidth = max(catColWidth, $0) }
                .frame(width: catColWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2){
                HStack(spacing: 6) {
                    sourceBadge(isFresh: vm.primaryIsFresh)
                    Text(vm.primaryTitle).font(.headline).lineLimit(1).truncationMode(.tail)
                        headerStatusIcon(
                            isUpdating: vm.primaryIsUpdating,
                            isFresh: vm.primaryIsFresh,
                            error: vm.primaryUpdateError
                        )
                }
                if let pid = vm.primaryConnection?.id {
                    Text(vm.primaryIsUpdating ? "Updating…" : vm.tsString(vm.connSnapshotTS[pid]))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: valColWidth, alignment: .leading)
            .help({
                guard let pid = vm.primaryConnection?.id else { return vm.primaryTitle }
                return vm.primaryIsUpdating
                  ? "\(vm.primaryTitle)\nUpdating"
                  : vm.columnHelp(vm.primaryTitle, isFresh: vm.primaryIsFresh, ts: vm.connSnapshotTS[pid])
            }())
        }
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func leftRow(rowIndex: Int, name n: String) -> some View {
        HStack(alignment: .top, spacing: rowHSpacing) {
            Text(n)
                .textSelection(.enabled)
                .lineLimit(1).truncationMode(.tail)
                .measureNameWidth { nameColWidth = max(nameColWidth, $0) }
                .frame(width: nameColWidth, alignment: .leading)

            Text(vm.category(for: n))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .measureCategoryWidth { catColWidth = max(catColWidth, $0) }
                .frame(width: catColWidth, alignment: .leading)

            valueDiffCell(primary: vm.primaryDB[n], secondary: nil)
                .frame(width: valColWidth, alignment: .leading)
        }
        .padding(.vertical, 6)
        .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.04))
        .overlay(Divider().opacity(0.15), alignment: .bottom)
    }

    // MARK: Separator

    private var separator: some View {
        Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 1)
    }

    // MARK: Right Pane

    @ViewBuilder
    private func secondaryConnectionsPane(shownNames: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                rightHeader
                Divider()
                rightRows(shownNames: shownNames)
            }
        }
    }

    private var rightHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: rowHSpacing) {
            ForEach(Array(vm.secondaryConnections.enumerated()), id: \.offset) { idx, conn in
                let title = vm.secondaryTitle(idx)
                let isUpd = vm.secondaryIsUpdating[idx] ?? false
                let fresh = vm.secondaryIsFresh[idx] ?? false

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        sourceBadge(isFresh: fresh)                                  // snapshot vs fresh
                           Text(title).font(.headline).lineLimit(1).truncationMode(.tail)
                           headerStatusIcon(
                               isUpdating: isUpd,
                               isFresh: fresh,
                               error: vm.secondaryUpdateErrors[conn.id]
                           )
                    }
                    Text(isUpd ? "Updating…" : vm.tsString(vm.connSnapshotTS[conn.id]))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: valColWidth, alignment: .leading)
                .help(isUpd
                      ? "\(title)\nUpdating"
                      : vm.columnHelp(title, isFresh: fresh, ts: vm.connSnapshotTS[conn.id]))

                Text("").font(.headline)
                    .frame(width: indColWidth, alignment: .center)
                    .help("Status vs Primary")
            }
        }
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func rightRows(shownNames: [String]) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(Array(shownNames.enumerated()), id: \.offset) { (rowIndex, name) in
                    RightRow(
                        vm: vm,
                        name: name,
                        valColWidth: valColWidth,
                        indColWidth: indColWidth,
                        rowHSpacing: rowHSpacing
                    )
                    .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.04))
                    .overlay(Divider().opacity(0.15), alignment: .bottom)
                }
            }
        }
    }
    
    // One row on the right side (all secondary columns for a single name)
    private struct RightRow: View {
        @ObservedObject var vm: CompareWindowViewModel
        let name: String
        let valColWidth: CGFloat
        let indColWidth: CGFloat
        let rowHSpacing: CGFloat

        var body: some View {
            // precompute once to keep the builder simple
            let primary = vm.primaryDB[name]

            return HStack(alignment: .top, spacing: rowHSpacing) {
                ForEach(0..<vm.secondaryConnections.count, id: \.self) { idx in
                    let secondary = vm.secondaryDBs[idx][name]
                    let status = vm.decideStatus(primary: primary, secondary: secondary)

                    ValueCell(
                        valuesToShow: secondary ?? primary,
                        isDifferent: status != .same,
                        width: valColWidth
                    )

                    StatusDot(status: status, width: indColWidth)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // The colored value box
    private struct ValueCell: View {
        let valuesToShow: [String]?
        let isDifferent: Bool
        let width: CGFloat

        var body: some View {
            let text = (valuesToShow?.isEmpty ?? true) ? "—" : valuesToShow!.joined(separator: ", ")

            return Text(text)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.vertical, 3)   // matches your cellVPad
                .padding(.horizontal, 4) // matches your cellHPad
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDifferent ? Color.orange.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isDifferent ? Color.orange.opacity(0.30) : Color.clear, lineWidth: 1)
                )
                .help(text)
                .frame(width: width, alignment: .leading)
        }
    }

    // The status icon cell
    private struct StatusDot: View {
        let status: CompareWindowViewModel.RowStatus
        let width: CGFloat

        var body: some View {
            Group {
                switch status {
                case .same:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Same")
                case .different:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).help("Different")
                case .onlyPrimary:
                    Image(systemName: "arrow.left.circle.fill").foregroundStyle(.blue).help("Only Primary")
                case .onlySecondary:
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(.purple).help("Only Secondary")
                }
            }
            .frame(width: width, alignment: .center)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Group {
                if !vm.lastError.isEmpty {
                    Text(vm.lastError).foregroundStyle(.red).lineLimit(2)
                } else if vm.isRefreshingPrimary {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Updating primary (\(vm.primaryTitle))…").foregroundStyle(.secondary)
                    }
                } else if vm.isRefreshingAllSecondary {
                    let updating = vm.secondaryIsUpdating.filter { $0 }.count
                    let totalR   = max(vm.secondaryConnections.count, 1)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Updating secondary connections… \(updating)/\(totalR)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let total = Set(payload.preferenceNames).count
                    let diffs = payload.preferenceNames.filter { vm.rowHasAnyDiff(name: $0) }.count
                    Text("Total: \(total) • Differences: \(diffs)").foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Close") { NSApplication.shared.keyWindow?.close() }
                .disabled(vm.isBusy)
        }
        .padding(.horizontal, edgeGutter)
        .padding(.vertical, 6)
    }

    // MARK: Small view helpers

    private func sourceBadge(isFresh: Bool) -> some View {
        Group {
            if isFresh { Image(systemName: "bolt.fill").foregroundStyle(.blue) }
            else { Image(systemName: "tray").foregroundStyle(.secondary) }
        }.font(.caption)
    }

    private func tinySpinner() -> some View {
        ProgressView().controlSize(.small).scaleEffect(0.7)
    }

    @ViewBuilder
    private func valueDiffCell(primary: [String]?, secondary: [String]?) -> some View {
        let show = secondary ?? primary
        let joined = (show?.isEmpty ?? true) ? "—" : show!.joined(separator: ", ")
        let isDifferent: Bool = { guard let s = secondary else { return false }
            return vm.decideStatus(primary: primary, secondary: s) != .same
        }()

        Text(joined)
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.vertical, cellVPad)
            .padding(.horizontal, cellHPad)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDifferent ? Color.orange.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDifferent ? Color.orange.opacity(0.30) : Color.clear, lineWidth: 1)
            )
            .help(joined)
    }

    private func statusDot(_ s: CompareWindowViewModel.RowStatus) -> some View {
        switch s {
        case .same:
            return Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Same")
        case .different:
            return Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).help("Different")
        case .onlyPrimary:
            return Image(systemName: "arrow.left.circle.fill").foregroundStyle(.blue).help("Only Primary")
        case .onlySecondary:
            return Image(systemName: "arrow.right.circle.fill").foregroundStyle(.purple).help("Only Secondary")
        }
    }
}

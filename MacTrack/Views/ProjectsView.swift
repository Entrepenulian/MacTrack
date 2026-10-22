import SwiftUI

/// Period the projects page sums over. Boundaries come from `Calendar.current`,
/// matching the per-entry week/month charts.
enum ProjectPeriod: String, CaseIterable, Identifiable {
    case today = "Today", week = "Week", month = "Month"
    var id: String { rawValue }

    var days: [String] {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return [DayKey.today]
        case .week:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
            return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
                .map { DayKey.key(for: $0) }
        case .month:
            let start = cal.dateInterval(of: .month, for: now)?.start ?? cal.startOfDay(for: now)
            let count = cal.range(of: .day, in: .month, for: now)?.count ?? 30
            return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
                .map { DayKey.key(for: $0) }
        }
    }
}

/// The projects page: which project is active, time per project for the selected
/// period, the apps/sites inside a project, the auto-switch rules, and archived
/// projects.
struct ProjectsView: View {
    @EnvironmentObject var store: UsageStore

    @State private var period: ProjectPeriod = .today
    @State private var selectedProjectID: String?
    @State private var editingID: String?          // nil = creating (when editorOpen)
    @State private var editorOpen = false
    @State private var draftName = ""
    @State private var draftColorHex = ""

    private static let palette = ["E0A45E", "5B9BF0", "5FC88F", "C79BE6", "E8736A",
                                  "4FC4C4", "E88FB6", "A6CC52", "7E86E0", "9C9CA8"]

    private var days: [String] { period.days }
    private var taggedSeconds: Double { store.taggedProjectSeconds(days: days) }
    private var unassignedSeconds: Double { max(0, store.totalSeconds(days: days) - taggedSeconds) }
    private var totals: [(project: Project, seconds: Double)] { store.projectTotals(days: days) }
    private var archivedProjects: [Project] {
        store.projects.filter(\.archived).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return store.projects.first { $0.id == id }
    }
    private var defaultColorHex: String {
        Self.palette[store.projects.count % Self.palette.count]
    }
    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activeCard
            periodPicker

            if let p = selectedProject {
                detail(for: p)
            } else {
                projectList
                autoSwitchSection
                if !archivedProjects.isEmpty { archivedSection }
                editorSection
            }
        }
    }

    private func percent(_ seconds: Double) -> Int {
        let base = taggedSeconds + unassignedSeconds
        guard base > 0 else { return 0 }
        return Int((seconds / base * 100).rounded())
    }

    // MARK: Active project

    private var activeCard: some View {
        LayeredCard(level: 1) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "Working on")
                    Spacer()
                    if store.activeProject != nil {
                        Button("Clear") { store.setActiveProject(nil) }
                            .buttonStyle(.plain)
                            .font(.rowMeta)
                            .foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                if let p = store.activeProject {
                    HStack(spacing: 6) {
                        Circle().fill(p.color).frame(width: 8, height: 8)
                        Text(p.name)
                            .font(.rowTitle)
                            .foregroundStyle(Theme.Ink.primary)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Space.sm)
                        Text(Format.duration(store.projectSeconds(p.id, days: ProjectPeriod.today.days)))
                            .font(.rowValue.monospacedDigit())
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                } else {
                    Text("No project yet. Right-click any app or site and choose Project.")
                        .font(.rowMeta)
                        .foregroundStyle(Theme.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: Period picker

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(ProjectPeriod.allCases) { p in
                Button {
                    withAnimation(.calm) { period = p; selectedProjectID = nil }
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(period == p ? Theme.Ink.primary : Theme.Ink.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(period == p ? Theme.fill(2) : Color.clear,
                                    in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Project list

    private var projectList: some View {
        VStack(spacing: 2) {
            SectionLabel(text: "Projects")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
            if totals.isEmpty {
                Text("No projects yet. Create one below.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                // Capped like SettingsView.excludedList, so a long project list
                // can't grow the popover unbounded.
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(totals, id: \.project.id) { row in
                            ProjectRow(
                                project: row.project,
                                seconds: row.seconds,
                                fraction: row.seconds / max(1, totals.first?.seconds ?? 1),
                                percent: percent(row.seconds),
                                onSelect: {
                                    withAnimation(.calm) { selectedProjectID = row.project.id }
                                },
                                onSetActive: { store.setActiveProject(row.project.id) },
                                onRename: {
                                    editingID = row.project.id
                                    draftName = row.project.name
                                    draftColorHex = row.project.colorHex
                                    editorOpen = true
                                },
                                onArchive: {
                                    store.setProjectArchived(id: row.project.id, archived: true)
                                    if selectedProjectID == row.project.id { selectedProjectID = nil }
                                }
                            )
                        }
                    }
                }
                .frame(height: min(CGFloat(totals.count), 8) * 36)
            }
            if unassignedSeconds > 0 { unassignedRow }
        }
    }

    private var unassignedRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.neutralSlice).frame(width: 8, height: 8)
            Text("Unassigned")
                .font(.rowTitle)
                .foregroundStyle(Theme.Ink.secondary)
            Spacer(minLength: Theme.Space.sm)
            Text(Format.duration(unassignedSeconds))
                .font(.rowValue.monospacedDigit())
                .foregroundStyle(Theme.Ink.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    // MARK: One project

    private func detail(for p: Project) -> some View {
        let items = store.projectItems(projectID: p.id, days: days)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.calm) { selectedProjectID = nil }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Ink.tertiary)
                    Circle().fill(p.color).frame(width: 8, height: 8)
                    Text(p.name)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Space.sm)
                    Text(Format.duration(store.projectSeconds(p.id, days: days)))
                        .font(.rowValue.monospacedDigit())
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: 30)

            if items.isEmpty {
                Text("No time in this period.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
            } else {
                // Capped like SettingsView.excludedList, so the popover can't grow
                // unbounded on a long list.
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(items) { item in
                            ProjectItemRow(entry: item)
                        }
                    }
                }
                .frame(height: min(CGFloat(items.count), 8) * 40)
            }
        }
    }

    // MARK: Auto-switch rules

    private var autoSwitchSection: some View {
        let keys = store.projectDefaults.keys.sorted()
        return VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Auto-switch")
                .padding(.bottom, 2)
            if keys.isEmpty {
                Text("Right-click a row and choose “Always use for this app” or “Always use for this site” to add a rule.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(keys, id: \.self) { key in
                            let target = store.projectDefaults[key].flatMap { id in
                                store.projects.first { $0.id == id }
                            }
                            HStack(spacing: 6) {
                                Text(store.projectDefaultLabel(key))
                                    .font(.rowTitle)
                                    .foregroundStyle(Theme.Ink.primary)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.Space.sm)
                                Text(target.map { $0.name + ($0.archived ? " (archived)" : "") } ?? "—")
                                    .font(.rowMeta)
                                    .foregroundStyle(target?.color ?? Theme.Ink.tertiary)
                                    .lineLimit(1)
                                Button {
                                    store.clearProjectDefault(forKey: key)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Theme.Ink.faint)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this rule")
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                        }
                    }
                }
                .frame(height: min(CGFloat(keys.count), 6) * 32)
            }
        }
    }

    // MARK: Archived

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Archived")
                .padding(.bottom, 2)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(archivedProjects) { p in
                        HStack(spacing: 8) {
                            Circle().fill(p.color).frame(width: 8, height: 8)
                            Text(p.name)
                                .font(.rowTitle)
                                .foregroundStyle(Theme.Ink.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: Theme.Space.sm)
                            Text(Format.duration(store.projectSeconds(p.id, days: days)))
                                .font(.rowMeta)
                                .foregroundStyle(Theme.Ink.tertiary)
                            Button("Restore") { store.setProjectArchived(id: p.id, archived: false) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.settingsAccent)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                    }
                }
            }
            .frame(height: min(CGFloat(archivedProjects.count), 4) * 32)
        }
    }

    // MARK: Editor

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editorOpen {
                LayeredCard(level: 1) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Project name", text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.rowTitle)
                            .foregroundStyle(Theme.Ink.primary)
                            .autocorrectionDisabled(true)
                        HStack(spacing: 6) {
                            ForEach(Self.palette, id: \.self) { hex in
                                Button { draftColorHex = hex } label: {
                                    Circle()
                                        .fill(Color(hex: UInt32(hex, radix: 16) ?? 0x70707A))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Circle().strokeBorder(
                                                draftColorHex == hex ? Theme.Ink.primary : Color.clear,
                                                lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 8) {
                            Spacer()
                            Button("Cancel") {
                                editorOpen = false
                                draftName = ""
                            }
                            .buttonStyle(.plain)
                            .font(.rowMeta)
                            .foregroundStyle(Theme.Ink.tertiary)
                            Button("Save") { save() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.settingsAccent)
                                .opacity(canSave ? 1 : 0.4)
                                .disabled(!canSave)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            } else {
                Button {
                    editingID = nil
                    draftName = ""
                    draftColorHex = defaultColorHex
                    editorOpen = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let id = editingID {
            store.renameProject(id: id, name: trimmed)
            store.setProjectColor(id: id, colorHex: draftColorHex)
        } else {
            store.createProject(name: trimmed, colorHex: draftColorHex)
        }
        editorOpen = false
        editingID = nil
        draftName = ""
    }
}

// MARK: - Rows

/// One project in the period ranking: dot, name, share percent, time, and a wash
/// bar sized by its share of the largest project.
private struct ProjectRow: View {
    let project: Project
    let seconds: Double
    let fraction: Double
    let percent: Int
    let onSelect: () -> Void
    let onSetActive: () -> Void
    let onRename: () -> Void
    let onArchive: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle().fill(project.color).frame(width: 8, height: 8)
                Text(project.name)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.sm)
                Text("\(percent)%")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
                Text(Format.duration(seconds))
                    .font(.rowValue.monospacedDigit())
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(project.color.opacity(0.16))
                            .frame(width: max(geo.size.width * CGFloat(fraction), 22))
                    }
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.calm) { hovering = h } }
        .contextMenu {
            Button("Set active", systemImage: "tag") { onSetActive() }
            Button("Rename…", systemImage: "pencil") { onRename() }
            Button("Archive", systemImage: "archivebox") { onArchive() }
        }
    }
}

/// One app or site inside a project — the same icon + wash row language as the
/// home list, without any of its actions.
private struct ProjectItemRow: View {
    let entry: UsageEntry

    var body: some View {
        HStack(spacing: 10) {
            switch entry.kind {
            case .app(let bundleID): AppIconView(bundleID: bundleID, size: 20)
            case .site(let domain): FaviconView(domain: domain, size: 20)
            }
            Text(entry.title)
                .font(.rowTitle)
                .foregroundStyle(Theme.Ink.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Space.sm)
            Text(Format.duration(entry.seconds))
                .font(.rowValue.monospacedDigit())
                .foregroundStyle(Theme.Ink.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: max(geo.size.width * CGFloat(entry.fraction), Theme.Radius.row * 2))
            }
        }
    }
}

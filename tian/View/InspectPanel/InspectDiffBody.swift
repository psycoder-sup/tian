import SwiftUI

/// Diff-tab body for the Inspect panel (FR-T10–T14, FR-T16, FR-T17, FR-T19).
///
/// Renders a single virtualized `LazyVStack` of flat row items — file
/// headers, hunk headers, individual diff lines, dividers. Flattening (vs.
/// nesting per-file VStacks of per-hunk VStacks) lets the outer LazyVStack
/// realize and recycle one row at a time, which is what makes a 5 000-line
/// diff scroll smoothly. Each row has a fixed height so SwiftUI doesn't
/// have to measure variable-height children to compute scroll offsets.
///
/// `InspectDiffViewModel` owns the debounced fetch + cancellation;
/// `InspectTabState` owns the per-file collapse map. ScrollViewReader uses
/// the named anchor `"diff-top"` so tab activation rebuilds scroll position
/// cheaply (FR-T04).
struct InspectDiffBody: View {
    @Bindable var viewModel: InspectDiffViewModel
    @Bindable var tabState: InspectTabState
    /// `true` when the active space's working directory is not inside a git
    /// repo. Per FR-T19 the body shows "Not in a git repository." instead.
    let isNoRepo: Bool

    /// Cached flat row list. Rebuilt only when `files` or `diffCollapse`
    /// changes, not on every body re-evaluation (e.g. hover, selection).
    @State private var cachedRows: [Row] = []

    // MARK: - Body

    var body: some View {
        if isNoRepo {
            InspectPanelMutedMessage("Not in a git repository.")
        } else if viewModel.isLoadingInitial {
            InspectPanelMutedMessage("Loading…")
        } else if viewModel.files.isEmpty {
            InspectPanelMutedMessage("No changes against HEAD.")
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("diff-top")
                        ForEach(cachedRows, id: \.id) { row in
                            view(for: row)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo("diff-top", anchor: .top)
                    cachedRows = makeRows()
                }
                .onChange(of: viewModel.files) { _, _ in cachedRows = makeRows() }
                .onChange(of: tabState.diffCollapse) { _, _ in cachedRows = makeRows() }
            }
        }
    }

    // MARK: - Flat row model

    private enum Row {
        case fileHeader(GitFileDiff)
        case binary(GitFileDiff)
        case hunkHeader(filePath: String, hunk: GitDiffHunk)
        case line(filePath: String, hunkID: Int, line: GitDiffLine)
        case truncated(filePath: String, hunkID: Int, count: Int)
        case divider(filePath: String)

        var id: String {
            switch self {
            case .fileHeader(let f):           return "fh:\(f.path)"
            case .binary(let f):               return "bn:\(f.path)"
            case .hunkHeader(let p, let h):    return "hh:\(p):\(h.id)"
            case .line(let p, let h, let l):   return "ln:\(p):\(h):\(l.id)"
            case .truncated(let p, let h, _):  return "tr:\(p):\(h)"
            case .divider(let p):              return "dv:\(p)"
            }
        }
    }

    private func makeRows() -> [Row] {
        var out: [Row] = []
        out.reserveCapacity(viewModel.files.count * 8)
        for file in viewModel.files {
            out.append(.fileHeader(file))
            let collapsed = tabState.diffCollapse[file.path] ?? false
            if !collapsed {
                if file.isBinary {
                    out.append(.binary(file))
                } else {
                    for hunk in file.hunks {
                        out.append(.hunkHeader(filePath: file.path, hunk: hunk))
                        for line in hunk.lines {
                            out.append(.line(
                                filePath: file.path,
                                hunkID: hunk.id,
                                line: line
                            ))
                        }
                        if hunk.truncatedLines > 0 {
                            out.append(.truncated(
                                filePath: file.path,
                                hunkID: hunk.id,
                                count: hunk.truncatedLines
                            ))
                        }
                    }
                }
            }
            out.append(.divider(filePath: file.path))
        }
        return out
    }

    @ViewBuilder
    private func view(for row: Row) -> some View {
        switch row {
        case .fileHeader(let file):
            DiffFileHeaderRow(
                file: file,
                isCollapsed: Binding(
                    get: { tabState.diffCollapse[file.path] ?? false },
                    set: { tabState.diffCollapse[file.path] = $0 }
                )
            )
        case .binary(let file):
            DiffBinaryPlaceholderRow(file: file)
        case .hunkHeader(_, let hunk):
            DiffHunkHeaderRow(header: hunk.header)
        case .line(_, _, let line):
            DiffLineRow(line: line)
        case .truncated(_, _, let count):
            DiffTruncatedRow(count: count)
        case .divider:
            Divider().background(Color.white.opacity(0.04))
        }
    }
}

// MARK: - Previews

#Preview("Diff body – loading") {
    let vm = InspectDiffViewModel()
    let state = InspectTabState(activeTab: .diff)
    InspectDiffBody(viewModel: vm, tabState: state, isNoRepo: false)
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Diff body – no-repo") {
    let vm = InspectDiffViewModel()
    let state = InspectTabState(activeTab: .diff)
    InspectDiffBody(viewModel: vm, tabState: state, isNoRepo: true)
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

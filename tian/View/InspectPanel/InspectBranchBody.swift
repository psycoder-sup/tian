import SwiftUI

/// Branch-tab body for the Inspect panel (FR-T20–T28).
///
/// Renders:
///   - Lane legend (FR-T23) — color swatch + label per lane, with the
///     trailing collapsed lane (`GitLane.collapsedID`) muted.
///   - Lane gutter overlay (FR-T22) — `BranchGraphCanvas` draws lane rails,
///     commit nodes (HEAD ring on the topmost), and parent edges as a single
///     `Canvas`. `.drawingGroup()` rasterizes through Metal so scrolling
///     stays smooth at 50 commits × 6 lanes.
///   - LazyVStack of `BranchCommitRow` rows over `viewModel.graph.commits`.
///
/// Empty/loading/no-repo handling per FR-T19 / FR-T26 / FR-T27.
struct InspectBranchBody: View {
    @Bindable var viewModel: InspectBranchViewModel
    /// `true` when the active space's working directory is not inside a git
    /// repo. FR-T19: no-repo wins over empty.
    let isNoRepo: Bool

    /// Per-row vertical pitch — shared with `BranchCommitRow.rowHeight`.
    private static let rowHeight: CGFloat = BranchCommitRow.rowHeight
    /// Per-lane horizontal pitch.
    private static let laneWidth: CGFloat = 14
    /// Padding between the rightmost rail and the commit text column.
    private static let gutterTrailingPadding: CGFloat = 8

    // MARK: - Body

    var body: some View {
        if isNoRepo {
            InspectPanelMutedMessage("Not in a git repository.")
        } else if viewModel.graph == nil && viewModel.isLoadingInitial {
            InspectPanelMutedMessage("Loading…")
        } else if let graph = viewModel.graph {
            graphBody(graph)
        } else {
            // Initial / unscheduled state — render a dim Loading… so the
            // body is never blank.
            InspectPanelMutedMessage("Loading…")
        }
    }

    // MARK: - Graph body

    @ViewBuilder
    private func graphBody(_ graph: GitCommitGraph) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("branch-top")

                    laneLegend(graph)

                    ZStack(alignment: .topLeading) {
                        BranchGraphCanvas(
                            graph: graph,
                            laneWidth: Self.laneWidth,
                            rowHeight: Self.rowHeight
                        )
                        // Match the lazy vstack origin so canvas + rows align.
                        .padding(.leading, 8)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(graph.commits, id: \.sha) { commit in
                                BranchCommitRow(
                                    commit: commit,
                                    lanes: graph.lanes,
                                    isHead: commit.sha == graph.commits.first?.sha,
                                    gutterWidth: gutterWidth(for: graph)
                                )
                            }
                        }
                    }
                }
            }
            .onAppear { proxy.scrollTo("branch-top", anchor: .top) }
        }
    }

    // MARK: - Lane legend (FR-T23)

    private func laneLegend(_ graph: GitCommitGraph) -> some View {
        HStack(spacing: 10) {
            ForEach(graph.lanes, id: \.id) { lane in
                HStack(spacing: 4) {
                    Circle()
                        .fill(BranchGraphCanvas.color(for: lane))
                        .frame(width: 7, height: 7)
                    Text(lane.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(
                            lane.isCollapsed
                                ? Color.primary.opacity(0.35)
                                : Color.primary.opacity(0.7)
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 32, alignment: .leading)
    }

    // MARK: - Geometry

    /// Width of the lane gutter that the canvas paints; commits in the row
    /// content reserve the same width via a leading spacer.
    private func gutterWidth(for graph: GitCommitGraph) -> CGFloat {
        let lanes = max(1, graph.lanes.count)
        return CGFloat(lanes) * Self.laneWidth + Self.gutterTrailingPadding
    }
}

// MARK: - Branch graph canvas (FR-T22)

/// `Canvas`-based lane rail / parent-edge overlay. Sized to the full graph
/// (one row per commit, one lane per `GitLane`). `.drawingGroup()` flattens
/// the result to a Metal-rasterized layer per Plan §6 risk note.
struct BranchGraphCanvas: View {
    let graph: GitCommitGraph
    let laneWidth: CGFloat
    let rowHeight: CGFloat

    private static let nodeRadius: CGFloat = 4
    private static let railLineWidth: CGFloat = 1

    /// Fixed palette indexed by `GitLane.colorIndex`.
    static let palette: [Color] = [
        Color(red: 96/255, green: 165/255, blue: 250/255),   // blue
        Color(red: 134/255, green: 239/255, blue: 172/255),  // green
        Color(red: 251/255, green: 146/255, blue: 60/255),   // orange
        Color(red: 192/255, green: 132/255, blue: 252/255),  // purple
        Color(red: 244/255, green: 114/255, blue: 182/255),  // pink
        Color(red: 45/255, green: 212/255, blue: 191/255),   // teal
        Color(red: 250/255, green: 204/255, blue: 21/255)    // yellow
    ]

    static func color(for lane: GitLane) -> Color {
        if lane.isCollapsed { return Color.primary.opacity(0.35) }
        return palette[lane.colorIndex % palette.count]
    }

    var body: some View {
        let columns = max(1, graph.lanes.count)
        let rows = graph.commits.count

        Canvas { ctx, _ in
            // Index commits by sha for parent-edge resolution.
            var rowBySha: [String: Int] = [:]
            rowBySha.reserveCapacity(rows)
            for (i, c) in graph.commits.enumerated() {
                rowBySha[c.sha] = i
            }

            // 1. Lane rails — per-lane, span only between the earliest (topmost)
            // and latest (bottommost) commit on that lane. Rails never extend
            // above the topmost or below the bottommost commit of the graph,
            // and lanes with a single visible commit get no rail at all (the
            // node alone tells the story).
            var laneRowRange: [Int: (top: Int, bottom: Int)] = [:]
            for (rowIndex, commit) in graph.commits.enumerated() {
                let lane = commit.laneIndex
                if let existing = laneRowRange[lane] {
                    laneRowRange[lane] = (
                        top: min(existing.top, rowIndex),
                        bottom: max(existing.bottom, rowIndex)
                    )
                } else {
                    laneRowRange[lane] = (top: rowIndex, bottom: rowIndex)
                }
            }
            for (laneIndex, range) in laneRowRange where range.top != range.bottom {
                let cx = CGFloat(laneIndex) * laneWidth + laneWidth / 2
                let yTop = CGFloat(range.top) * rowHeight + rowHeight / 2
                let yBottom = CGFloat(range.bottom) * rowHeight + rowHeight / 2
                var path = Path()
                path.move(to: CGPoint(x: cx, y: yTop))
                path.addLine(to: CGPoint(x: cx, y: yBottom))
                let color = laneIndex < graph.lanes.count
                    ? Self.color(for: graph.lanes[laneIndex]).opacity(0.35)
                    : Color.primary.opacity(0.15)
                ctx.stroke(path, with: .color(color), lineWidth: Self.railLineWidth)
            }

            // 2. Parent edges — connect each commit to each parent's row.
            for (rowIndex, commit) in graph.commits.enumerated() {
                let cx = CGFloat(commit.laneIndex) * laneWidth + laneWidth / 2
                let cy = CGFloat(rowIndex) * rowHeight + rowHeight / 2

                for parentSha in commit.parentShas {
                    guard let parentRow = rowBySha[parentSha] else { continue }
                    let parent = graph.commits[parentRow]
                    let pcx = CGFloat(parent.laneIndex) * laneWidth + laneWidth / 2
                    let pcy = CGFloat(parentRow) * rowHeight + rowHeight / 2

                    var path = Path()
                    let yStart = cy + Self.nodeRadius
                    let yEnd = pcy - Self.nodeRadius
                    path.move(to: CGPoint(x: cx, y: yStart))
                    if pcx == cx {
                        path.addLine(to: CGPoint(x: pcx, y: yEnd))
                    } else {
                        // Vertical run on the side (higher-x) lane plus a
                        // short S-curve at the junction with main. Short edges
                        // skip the line and use a midpoint cubic so the curve
                        // doesn't degenerate.
                        let totalSpan = yEnd - yStart
                        let junctionH = min(rowHeight * 1.6, max(rowHeight * 0.9, totalSpan * 0.6))
                        let childIsSide = cx > pcx
                        let curveStartY = totalSpan <= rowHeight * 1.2
                            ? yStart
                            : (childIsSide ? yEnd - junctionH : yStart)
                        let curveEndY = totalSpan <= rowHeight * 1.2
                            ? yEnd
                            : (childIsSide ? yEnd : yStart + junctionH)
                        let curveMidY = (curveStartY + curveEndY) / 2

                        if childIsSide && curveStartY > yStart {
                            path.addLine(to: CGPoint(x: cx, y: curveStartY))
                        }
                        path.addCurve(
                            to: CGPoint(x: pcx, y: curveEndY),
                            control1: CGPoint(x: cx, y: curveMidY),
                            control2: CGPoint(x: pcx, y: curveMidY)
                        )
                        if !childIsSide && curveEndY < yEnd {
                            path.addLine(to: CGPoint(x: pcx, y: yEnd))
                        }
                    }
                    let edgeColor = (commit.laneIndex < graph.lanes.count)
                        ? Self.color(for: graph.lanes[commit.laneIndex]).opacity(0.6)
                        : Color.primary.opacity(0.4)
                    ctx.stroke(path, with: .color(edgeColor), lineWidth: 1)
                }
            }

            // 3. Commit nodes (HEAD ring on row 0).
            for (rowIndex, commit) in graph.commits.enumerated() {
                let cx = CGFloat(commit.laneIndex) * laneWidth + laneWidth / 2
                let cy = CGFloat(rowIndex) * rowHeight + rowHeight / 2
                let nodeColor = (commit.laneIndex < graph.lanes.count)
                    ? Self.color(for: graph.lanes[commit.laneIndex])
                    : Color.primary.opacity(0.5)
                let nodeRect = CGRect(
                    x: cx - Self.nodeRadius,
                    y: cy - Self.nodeRadius,
                    width: Self.nodeRadius * 2,
                    height: Self.nodeRadius * 2
                )
                let path = Path(ellipseIn: nodeRect)
                if commit.isMerge {
                    // Merge commit: hollow ring.
                    ctx.stroke(path, with: .color(nodeColor), lineWidth: 1.25)
                } else {
                    ctx.fill(path, with: .color(nodeColor))
                }

                if rowIndex == 0 {
                    // HEAD ring (FR-T21 / FR-T22).
                    let ringRect = nodeRect.insetBy(dx: -2.5, dy: -2.5)
                    let ringPath = Path(ellipseIn: ringRect)
                    ctx.stroke(ringPath, with: .color(nodeColor.opacity(0.85)), lineWidth: 1)
                }
            }
        }
        .frame(
            width: CGFloat(columns) * laneWidth,
            height: CGFloat(max(rows, 1)) * rowHeight,
            alignment: .topLeading
        )
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Branch body – loading") {
    let vm = InspectBranchViewModel()
    InspectBranchBody(viewModel: vm, isNoRepo: false)
        .frame(width: 480, height: 600)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Branch body – no-repo") {
    let vm = InspectBranchViewModel()
    InspectBranchBody(viewModel: vm, isNoRepo: true)
        .frame(width: 480, height: 600)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

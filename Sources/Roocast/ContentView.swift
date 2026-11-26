import SwiftUI
import AppKit

/// Shared panel geometry — keep `LauncherPanel` and SwiftUI content in sync.
enum LauncherLayout {
    static let width: CGFloat = 640
    /// Results area stays ~400; footer adds Raycast-style hint bar below.
    static let height: CGFloat = 400 + footerHeight
    static let cornerRadius: CGFloat = 10
    /// Raycast-style bottom hint bar (Open ↵ · Actions ⌘K).
    static let footerHeight: CGFloat = 32
}

struct ContentView: View {
    @ObservedObject var searchSession: SearchSession
    @ObservedObject var navigationState: NavigationState
    @ObservedObject var menuModel: LauncherActionsModel
    @ObservedObject var rankPreferences: SearchRankPreferences
    @StateObject private var appIndex = AppIndex()
    @FocusState private var isSearchFocused: Bool
    /// Hide the launcher. `restoreFocus` is false for app handoff (target activates itself).
    let onDismiss: (_ restoreFocus: Bool) -> Void
    /// Snap/maximize the prior focused window. Panel supplies AX target.
    var onWindowSnap: ((WindowSnap.Command) -> Void)? = nil
    /// Start (or replace) the Dynamic Island countdown pill.
    var onCountdown: ((Int) -> Void)? = nil

    var filteredApps: [AppItem] {
        appIndex.search(searchSession.searchQuery, demoteLevels: rankPreferences.demoteLevels)
    }

    private var fieldText: Binding<String> {
        Binding(
            get: {
                searchSession.lockedVerb == nil ? searchSession.query : searchSession.argument
            },
            set: { newValue in
                if searchSession.lockedVerb == nil {
                    searchSession.query = newValue
                } else {
                    searchSession.argument = newValue
                }
            }
        )
    }

    private var menuHeight: CGFloat {
        48 + CGFloat(menuModel.actions.count) * 30
    }

    private var listViewportHeight: CGFloat {
        LauncherLayout.height
            - LauncherMenuLayout.headerHeight
            - LauncherLayout.footerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            resultsArea
            actionsFooter
        }
        .frame(width: LauncherLayout.width, height: LauncherLayout.height)
        // Solid underlay first: SwiftUI materials can draw blank while Roocast is inactive
        // (nonactivating panel keeps Ghostty frontmost).
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous)
                    .fill(.thickMaterial)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous))
        .onAppear {
            wireMenuCallbacks()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
            navigationState.sync(itemCount: filteredApps.count)
        }
        // onReceive keeps SwiftUI state live (addObserver captured a stale View copy).
        .onReceive(NotificationCenter.default.publisher(for: .launchSelectedApp)) { _ in
            launchSelectedApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherWillShow)) { _ in
            menuModel.close()
            searchSession.clear()
            // Reset selection immediately; after reindex only refresh bounds so ↑/↓
            // during the scan is not yanked back to row 0.
            navigationState.sync(itemCount: filteredApps.count)
            Task {
                await appIndex.indexApps()
                navigationState.updateBounds(itemCount: filteredApps.count)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: searchSession.query) { _, _ in
            refreshAfterQueryChange()
        }
        .onChange(of: searchSession.argument) { _, _ in
            refreshAfterQueryChange()
        }
        .onChange(of: searchSession.lockedVerb) { _, _ in
            refreshAfterQueryChange()
        }
        // Empty-summon list appears when indexing finishes — query never changes, so
        // refresh arrow bounds whenever the index updates.
        .onChange(of: appIndex.apps) { _, _ in
            navigationState.updateBounds(itemCount: filteredApps.count)
        }
        .onChange(of: appIndex.zoxideItem) { _, _ in
            navigationState.updateBounds(itemCount: filteredApps.count)
        }
        .onChange(of: rankPreferences.demoteLevels) { _, _ in
            navigationState.updateBounds(itemCount: filteredApps.count)
        }
        .environmentObject(navigationState)
    }

    // MARK: - Sub-views

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)

            if let lockedVerb = searchSession.lockedVerb {
                Text(lockedVerb)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
                    .accessibilityLabel("Locked command \(lockedVerb)")
            }

            SearchField(
                text: fieldText,
                placeholder: searchSession.fieldPlaceholder,
                onSubmit: { launchSelectedApp() },
                onComplete: { searchSession.tryLockCommand() },
                onBackspaceWhenEmpty: { searchSession.unlockCommand() }
            )
            .frame(height: 28)

            if searchSession.showsClearButton {
                Button(action: { searchSession.clear() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func refreshAfterQueryChange() {
        // Async zoxide — must not run inside `filteredApps` / body (Process nested
        // the run loop during layout and SIGABRT'd AttributeGraph).
        appIndex.scheduleZoxide(for: searchSession.searchQuery)
        navigationState.sync(itemCount: filteredApps.count)
        if menuModel.isOpen { menuModel.close() }
    }

    private var resultsArea: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if filteredApps.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: searchSession.searchQuery.isEmpty ? "keyboard" : "magnifyingglass")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text(searchSession.searchQuery.isEmpty ? "Start typing to search…" : "No results")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 36)
                        } else {
                            ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                                // Identity must be the app id — `.id(index)` reused empty-summon
                                // Firefox rows when the query changed (Notes looked "missing").
                                AppRow(app: app, isSelected: index == navigationState.selectedIndex)
                                    .id(app.id)
                                    .onTapGesture {
                                        navigationState.selectedIndex = index
                                        launchSelectedApp()
                                    }
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .onAppear {
                                                    menuModel.rowFrames[app.id] = geo.frame(
                                                        in: .named("launcherList")
                                                    )
                                                }
                                                .onChange(of: geo.frame(in: .named("launcherList"))) { _, frame in
                                                    menuModel.rowFrames[app.id] = frame
                                                    if menuModel.isOpen, menuModel.anchoredItem?.id == app.id {
                                                        menuModel.close()
                                                    }
                                                }
                                        }
                                    )
                            }
                        }
                    }
                    // Reindex must not animate rows into a new order (reads as a sudden jump).
                    .transaction { $0.animation = nil }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .coordinateSpace(name: "launcherList")
                .onChange(of: navigationState.selectedIndex) { _, index in
                    // No `.center` — that over-scrolled short lists so row 3 lost its highlight.
                    guard filteredApps.indices.contains(index) else { return }
                    proxy.scrollTo(filteredApps[index].id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if menuModel.isOpen {
                actionsMenuOverlay
            }
        }
        // DIAG: prove ⌘K twitch — overlay fixed height vs live results area.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        FocusRestorer.log(
                            "actionsMenu diag: resultsArea.h=\(geo.size.height) overlayConst=\(listViewportHeight) headerConst=\(LauncherMenuLayout.headerHeight) menuOpen=\(menuModel.isOpen)"
                        )
                    }
                    .onChange(of: geo.size.height) { _, h in
                        FocusRestorer.log(
                            "actionsMenu diag: resultsArea.h changed → \(h) overlayConst=\(listViewportHeight) menuOpen=\(menuModel.isOpen)"
                        )
                    }
                    .onChange(of: menuModel.isOpen) { _, open in
                        FocusRestorer.log(
                            "actionsMenu diag: isOpen=\(open) resultsArea.h=\(geo.size.height) overlayConst=\(listViewportHeight) delta=\(geo.size.height - listViewportHeight)"
                        )
                    }
            }
        )
    }

    /// Raycast-style hint row: primary action + Actions ⌘K.
    private var actionsFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            HStack(spacing: 0) {
                Text("v\(AppVersion.string)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text("Open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    KeyboardKeycap(label: "↵")
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 10)
                HStack(spacing: 5) {
                    Text("Actions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    KeyboardKeycap(label: "⌘")
                    KeyboardKeycap(label: "K")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: LauncherLayout.footerHeight - 1)
        }
        .frame(height: LauncherLayout.footerHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open, Return. Actions, Command K.")
    }

    /// The actions menu, anchored below the selected row (above if it would
    /// run past the fold), clamped inside the list's viewport.
    @ViewBuilder
    private var actionsMenuOverlay: some View {
        let anchor = menuModel.anchorFrame
        let listHeight = listViewportHeight
        let belowCenter = anchor.maxY + 6 + menuHeight / 2
        let aboveCenter = anchor.minY - 6 - menuHeight / 2
        let useBelow = belowCenter + menuHeight / 2 <= listHeight || aboveCenter - menuHeight / 2 < 0
        let centerX = min(
            max(anchor.midX, LauncherMenuLayout.menuWidth / 2 + 8),
            LauncherLayout.width - LauncherMenuLayout.menuWidth / 2 - 8
        )
        let centerY = min(
            max(useBelow ? belowCenter : aboveCenter, menuHeight / 2 + 8),
            listHeight - menuHeight / 2 - 8
        )
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { menuModel.close() }
            LauncherActionsMenuView(model: menuModel)
                .position(x: centerX, y: centerY)
        }
        .frame(width: LauncherLayout.width, height: listHeight)
    }

    // MARK: - Behavior

    private func wireMenuCallbacks() {
        // ⌘K toggle target: the highlighted row. Set here so the closure
        // always reads live state (query filters, selected row).
        menuModel.onToggle = { [self] in
            guard !filteredApps.isEmpty,
                  navigationState.selectedIndex < filteredApps.count else { return }
            let item = filteredApps[navigationState.selectedIndex]
            menuModel.open(
                for: item,
                anchorFrame: menuModel.rowFrames[item.id] ?? .zero,
                isDemoted: rankPreferences.isDemoted(item.id)
            )
        }
        menuModel.onPerform = { [self] action in
            guard let item = menuModel.anchoredItem else { return }
            switch action {
            case .open:
                menuModel.close()
                if let index = filteredApps.firstIndex(where: { $0.id == item.id }) {
                    navigationState.selectedIndex = index
                }
                launchSelectedApp()
            case .decreaseRanking:
                rankPreferences.decreaseRanking(for: item.id)
                menuModel.close()
            case .resetRanking:
                rankPreferences.resetRanking(for: item.id)
                menuModel.close()
            }
        }
    }

    private func launchSelectedApp() {
        guard !filteredApps.isEmpty else { return }
        guard navigationState.selectedIndex < filteredApps.count else { return }

        let app = filteredApps[navigationState.selectedIndex]

        if case .calculator(let copyText) = app.kind {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyText, forType: .string)
            searchSession.clear()
            onDismiss(false)
            return
        }

        if case .countdown(let seconds) = app.kind {
            searchSession.clear()
            onCountdown?(seconds)
            onDismiss(false)
            return
        }

        if app.kind == .countdownHint {
            // Keep the panel open — user still needs a duration argument.
            return
        }

        if app.kind == .quit {
            searchSession.clear()
            NSApplication.shared.terminate(nil)
            return
        }

        if app.kind == .checkForUpdates {
            searchSession.clear()
            onDismiss(false)
            Task { @MainActor in
                let outcome = await UpdateCheck.check()
                UpdateCheck.present(outcome)
            }
            return
        }

        if app.kind == .uninstall {
            searchSession.clear()
            onDismiss(false)
            UninstallRoocast.run()
            return
        }

        if app.kind == .leftHalf {
            searchSession.clear()
            onWindowSnap?(.left)
            return
        }

        if app.kind == .rightHalf {
            searchSession.clear()
            onWindowSnap?(.right)
            return
        }

        if app.kind == .maximize {
            searchSession.clear()
            onWindowSnap?(.maximize)
            return
        }

        if app.kind == .reasonableSize {
            searchSession.clear()
            onWindowSnap?(.reasonableSize)
            return
        }

        if app.kind == .topHalf {
            searchSession.clear()
            onWindowSnap?(.top)
            return
        }

        if app.kind == .bottomHalf {
            searchSession.clear()
            onWindowSnap?(.bottom)
            return
        }

        if app.kind == .firstThird {
            searchSession.clear()
            onWindowSnap?(.firstThird)
            return
        }

        if app.kind == .lastTwoThirds {
            searchSession.clear()
            onWindowSnap?(.lastTwoThirds)
            return
        }

        if app.kind == .moveToTop {
            searchSession.clear()
            onWindowSnap?(.moveToTop)
            return
        }

        if app.kind == .moveToBottom {
            searchSession.clear()
            onWindowSnap?(.moveToBottom)
            return
        }

        if app.kind == .moveToLeft {
            searchSession.clear()
            onWindowSnap?(.moveToLeft)
            return
        }

        if app.kind == .moveToRight {
            searchSession.clear()
            onWindowSnap?(.moveToRight)
            return
        }

        // Clear so the next open starts with an empty search field.
        searchSession.clear()

        // Tinycast-style: dismiss first, then fire launch (see LaunchHandoffPlan).
        if app.kind == .folder {
            executeLaunchHandoff(LaunchHandoffPlan.forFolder(path: app.path))
            return
        }

        if let profile = app.profile {
            executeLaunchHandoff(
                LaunchHandoffPlan.forFirefoxProfile(profile: profile, path: app.path)
            )
        } else {
            executeLaunchHandoff(LaunchHandoffPlan.forApplication(path: app.path))
        }
    }

    /// Runs a tested handoff plan in order (dismiss → activate/open).
    private func executeLaunchHandoff(_ plan: LaunchHandoffPlan) {
        for step in plan.steps {
            switch step {
            case .dismissPanel:
                onDismiss(plan.restoreFocus)
            case .activateOrLaunch(let path):
                AppActivator.activateOrLaunch(
                    appPath: path,
                    allowsRunningApplicationSubstitution: plan.allowsRunningApplicationSubstitution
                )
            case .launchFirefoxProfile(let profile, let path):
                AppLauncher.launchFirefoxProfile(profile: profile, appPath: path)
            case .openFolder(let path):
                NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
    }
}

struct AppRow: View {
    let app: AppItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                }

                // Running indicator — white on selected row (accent bg), accent otherwise
                if app.isRunning {
                    Circle()
                        .fill(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 26, height: 26)

            // Name only — no filesystem paths. Profile stays as a quiet label when needed.
            // Calculator: answer first, expression as the quiet echo (Tinycast lead-row shape).
            if case .calculator = app.kind {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    if let expression = app.profile {
                        Text(expression)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)

                    if let profile = app.profile {
                        Text(profile)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Selection only — no idle row chrome.
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
    }
}

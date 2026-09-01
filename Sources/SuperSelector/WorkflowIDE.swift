import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class WorkflowIDEModel {
  var log: SuperSelectorWorkflowLog
  var selectedWorkflowID: UUID?
  var selectedStepID: UUID?
  var editorJSON = ""
  var status = "Ready"
  var replayProgress: Int?
  var isReplaying = false
  var stepDelay = 0.7

  @ObservationIgnored var onLogChanged: (() -> Void)?
  @ObservationIgnored var prepareVisualDebugging: (() -> Void)?
  @ObservationIgnored var finishVisualDebugging: (() -> Void)?
  @ObservationIgnored var prepareReplayVisualization: (() -> Void)?
  @ObservationIgnored var finishReplayVisualization: (() -> Void)?
  @ObservationIgnored var prepareNewTrail: (() -> Void)?
  @ObservationIgnored var finishNewTrail: (() -> Void)?
  @ObservationIgnored var showReplayTarget: ((ResolvedSelectorTarget) -> Void)?
  @ObservationIgnored var restoreIDE: (() -> Void)?
  @ObservationIgnored
  var showResolved: ((String, String, @escaping (Result<Void, Error>) -> Void) -> Void)?
  @ObservationIgnored private let replayer = MacWorkflowReplayer()
  @ObservationIgnored private let persistenceURL: URL
  @ObservationIgnored private let screenshotStore: WorkflowScreenshotStore
  @ObservationIgnored private let persistenceQueue = DispatchQueue(
    label: "SuperSelector.WorkflowPersistence", qos: .utility)
  @ObservationIgnored private var replayTask: Task<Void, Never>?
  @ObservationIgnored private var replayGeneration: UInt = 0

  init(dataPaths: SuperSelectorDataPaths = .canonical()) {
    try? dataPaths.prepare()
    persistenceURL = dataPaths.workflowLog
    screenshotStore = WorkflowScreenshotStore(directory: dataPaths.screenshots)
    var loaded = (try? SuperSelectorWorkflowLog.read(from: persistenceURL)) ?? .init()
    if !loaded.screenshotAssets.isEmpty {
      // Schema-2 logs originally embedded every JPEG as base64. Move those payloads to
      // individual files once, then keep the hot observable model metadata-only.
      if (try? screenshotStore.store(loaded.screenshotAssets)) != nil {
        loaded.screenshotAssets = [:]
        try? loaded.write(to: persistenceURL)
      }
    }
    log = loaded
    selectedWorkflowID = log.workflows.first?.id
    selectedStepID = selectedWorkflow?.breadcrumbs.last?.id
  }

  var selectedWorkflow: SuperSelectorWorkflow? {
    guard let selectedWorkflowID else { return nil }
    return log.workflows.first { $0.id == selectedWorkflowID }
  }

  var selectedStepIndex: Int? {
    guard let workflow = selectedWorkflow, let selectedStepID else { return nil }
    return workflow.breadcrumbs.firstIndex { $0.id == selectedStepID }
  }

  var selectedStep: SuperSelectorWorkflowStep? {
    guard let workflow = selectedWorkflow else { return nil }
    if let selectedStepIndex { return workflow.breadcrumbs[selectedStepIndex] }
    return workflow.breadcrumbs.last
  }

  func record(selector: String, trail: BreadcrumbTrail, at date: Date = Date()) {
    var workflow = SuperSelectorWorkflow(
      name: Self.workflowName(for: selector),
      trail: trail,
      finalSelector: selector,
      at: date
    )
    for screenshot in trail.links.compactMap(\.screenshot) {
      try? screenshotStore.store(
        WorkflowScreenshotAsset(
          id: screenshot.id,
          jpegData: screenshot.jpegData
        ))
    }
    if let existing = log.workflows.first(where: { $0.finalSelector == selector }) {
      workflow.id = existing.id
      workflow.createdAt = existing.createdAt
    }
    log.workflows.removeAll { $0.finalSelector == selector }
    log.workflows.insert(workflow, at: 0)
    if log.workflows.count > 100 { log.workflows.removeLast(log.workflows.count - 100) }
    pruneScreenshotAssets()
    selectedWorkflowID = workflow.id
    selectedStepID = workflow.breadcrumbs.last?.id
    changed("Recorded \(workflow.name)")
  }

  func selectWorkflow(_ id: UUID?) {
    selectedWorkflowID = id
    selectedStepID = selectedWorkflow?.breadcrumbs.last?.id
    editorJSON = ""
  }

  func selectStep(_ id: UUID?) {
    selectedStepID = id ?? selectedWorkflow?.breadcrumbs.last?.id
  }

  func renameWorkflow(_ id: UUID, to name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, let index = log.workflows.firstIndex(where: { $0.id == id }) else {
      return
    }
    log.workflows[index].name = name
    log.workflows[index].updatedAt = Date()
    changed("Renamed trail")
  }

  func deleteSelected() {
    guard let id = selectedWorkflowID else { return }
    log.remove(id: id)
    pruneScreenshotAssets()
    selectedWorkflowID = log.workflows.first?.id
    selectedStepID = selectedWorkflow?.breadcrumbs.last?.id
    changed("Deleted workflow")
  }

  func clearAllWorkflows() {
    log = .init()
    selectedWorkflowID = nil
    selectedStepID = nil
    replayProgress = nil
    editorJSON = ""
    pruneScreenshotAssets()
    changed("Cleared all recent trails")
  }

  func startNewTrail(clearHistory: Bool = false) {
    if clearHistory { clearAllWorkflows() }
    prepareNewTrail?()
    status = "Showing desktop…"
    Task { [weak self] in
      guard let self else { return }
      do {
        try await replayer.resetToNormalizedDesktop()
        finishNewTrail?()
        status = "Recording a new trail"
      } catch {
        finishNewTrail?()
        status = "Desktop reset failed: \(error.localizedDescription)"
      }
    }
  }

  func applyEditorJSON() {
    do {
      let imported = try SuperSelectorWorkflowLog(jsonData: Data(editorJSON.utf8))
      guard let workflow = imported.workflows.first else {
        throw SuperSelectorWorkflowError.invalidStepIndex(0)
      }
      try screenshotStore.store(imported.screenshotAssets)
      log.upsert(workflow)
      selectedWorkflowID = workflow.id
      selectedStepID = workflow.breadcrumbs.last?.id
      changed("Applied JSON edits")
    } catch {
      status = "JSON error: \(error.localizedDescription)"
    }
  }

  func loadEditorJSON() {
    syncEditor()
    status = editorJSON.isEmpty ? "Unable to load workflow JSON" : "Loaded editable JSON"
  }

  func copySelectedJSON() {
    guard let workflow = selectedWorkflow else { return }
    do {
      try hydratedLog(workflows: [workflow]).copyJSON(to: .general)
      status = "Copied workflow JSON"
    } catch { status = error.localizedDescription }
  }

  func copyAllJSON() {
    do {
      try hydratedLog(workflows: log.workflows).copyJSON(to: .general)
      status = "Copied \(log.workflows.count) workflows"
    } catch { status = error.localizedDescription }
  }

  func importClipboard() {
    do {
      merge(try SuperSelectorWorkflowLog.read(from: .general))
      changed("Imported workflow JSON from clipboard")
    } catch { status = error.localizedDescription }
  }

  func importFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      merge(try SuperSelectorWorkflowLog.read(from: url))
      changed("Imported \(url.lastPathComponent)")
    } catch { status = error.localizedDescription }
  }

  func exportSelectedFile() {
    guard let workflow = selectedWorkflow else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = Self.safeFilename(workflow.name) + ".json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try hydratedLog(workflows: [workflow]).write(to: url)
      status = "Exported \(url.lastPathComponent)"
    } catch { status = error.localizedDescription }
  }

  func gotoSelected() {
    guard let workflow = selectedWorkflow else { return }
    let selector =
      selectedStepIndex.map { workflow.breadcrumbs[$0].selector }
      ?? workflow.finalSelector
    visualize(selector: selector, breadcrumbs: workflow.renderedBreadcrumbs())
  }

  func replayToSelected() {
    guard let workflow = selectedWorkflow, !workflow.breadcrumbs.isEmpty else { return }
    let index =
      selectedStepIndex ?? workflow.breadcrumbs.index(before: workflow.breadcrumbs.endIndex)
    do { replay(try workflow.replayPlan(through: index), workflow: workflow) } catch {
      status = error.localizedDescription
    }
  }

  func replayAll() {
    guard let workflow = selectedWorkflow, !workflow.breadcrumbs.isEmpty else { return }
    replay(workflow.gotoPlan, workflow: workflow)
  }

  func cancelReplay() {
    replayGeneration &+= 1
    let task = replayTask
    replayTask = nil
    task?.cancel()
    isReplaying = false
    finishReplayVisualization?()
    status = "Replay cancelled"
  }

  private func replay(_ plan: SuperSelectorReplayPlan, workflow: SuperSelectorWorkflow) {
    replayGeneration &+= 1
    let generation = replayGeneration
    let previousTask = replayTask
    replayTask = nil
    previousTask?.cancel()
    prepareReplayVisualization?()
    isReplaying = true
    replayProgress = nil
    status = "Resetting to normalized desktop…"
    replayTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await replayer.execute(plan, stepDelay: stepDelay) {
          [weak self] index, step, target in
          guard self?.replayGeneration == generation else { return }
          self?.replayProgress = index
          self?.status = "Replaying \(index + 1)/\(plan.steps.count): \(step.action.summary)"
          self?.showReplayTarget?(target)
        }
        guard replayGeneration == generation else { return }
        replayTask = nil
        isReplaying = false
        finishReplayVisualization?()
        visualize(
          selector: plan.highlightSelector,
          breadcrumbs: workflow.renderedBreadcrumbs(through: plan.steps.count - 1)
        )
      } catch is CancellationError {
        guard replayGeneration == generation else { return }
        replayTask = nil
        isReplaying = false
        finishReplayVisualization?()
        status = "Replay cancelled"
      } catch {
        guard replayGeneration == generation else { return }
        replayTask = nil
        isReplaying = false
        finishReplayVisualization?()
        status = "Replay stopped: \(error.localizedDescription)"
        restoreIDE?()
      }
    }
  }

  private func visualize(selector: String, breadcrumbs: String) {
    prepareVisualDebugging?()
    status = "Resolving selector…"
    showResolved?(selector, breadcrumbs) { [weak self] result in
      self?.finishVisualDebugging?()
      switch result {
      case .success: self?.status = "Resolved and highlighted"
      case .failure(let error):
        self?.status = "Resolve failed: \(error.localizedDescription)"
        self?.restoreIDE?()
      }
    }
  }

  private func merge(_ imported: SuperSelectorWorkflowLog) {
    for workflow in imported.workflows.reversed() { log.upsert(workflow) }
    try? screenshotStore.store(imported.screenshotAssets)
    selectedWorkflowID = imported.workflows.first?.id ?? selectedWorkflowID
    selectedStepID = selectedWorkflow?.breadcrumbs.last?.id
  }

  private func pruneScreenshotAssets() {
    let retained = Set(
      log.workflows.flatMap { workflow in
        workflow.breadcrumbs.compactMap { $0.screenshot?.assetID }
      })
    screenshotStore.prune(retaining: retained)
  }

  private func changed(_ message: String) {
    let snapshot = log
    let url = persistenceURL
    persistenceQueue.async { try? snapshot.write(to: url) }
    editorJSON = ""
    status = message
    onLogChanged?()
  }

  func flushPersistence() {
    persistenceQueue.sync {}
  }

  func setStudioVisible(_ visible: Bool) {
    if !visible { editorJSON = "" }
  }

  func screenshotData(for id: UUID) -> Data? {
    screenshotStore.data(for: id)
  }

  private func hydratedLog(workflows: [SuperSelectorWorkflow]) -> SuperSelectorWorkflowLog {
    let ids = Set(
      workflows.flatMap { workflow in
        workflow.breadcrumbs.compactMap { $0.screenshot?.assetID }
      })
    return SuperSelectorWorkflowLog(
      workflows: workflows,
      screenshotAssets: screenshotStore.assets(for: ids)
    )
  }

  private func syncEditor() {
    guard let workflow = selectedWorkflow,
      // The editor is for workflow structure. Embedding base64 screenshots here makes
      // TextEditor repeatedly lay out tens or hundreds of megabytes of invisible data.
      let data = try? SuperSelectorWorkflowLog(workflows: [workflow]).jsonData()
    else {
      editorJSON = ""
      return
    }
    editorJSON = String(decoding: data, as: UTF8.self)
  }

  private static func workflowName(for selector: String) -> String {
    let hints = (try? SuperSelectorDecoder.decode(selector)) ?? []
    func value(_ kind: String) -> String? { hints.first { $0.kind == kind }?.value }
    return [
      value("application.name") ?? value("application.bundle-id") ?? "Screen",
      value("semantic.name") ?? value("semantic.value") ?? value("semantic.role") ?? "target",
    ].joined(separator: " · ")
  }

  private static func safeFilename(_ value: String) -> String {
    value.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
}

final class WorkflowIDEWindowController: NSWindowController, NSWindowDelegate {
  var onVisibilityChanged: ((Bool) -> Void)?

  init(model: WorkflowIDEModel) {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 1280, height: 780),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "SuperSelector Studio"
    window.subtitle = "CUA workflow recorder and time-travel debugger"
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.minSize = CGSize(width: 980, height: 620)
    window.center()
    window.contentViewController = NSHostingController(rootView: WorkflowIDEView(model: model))
    super.init(window: window)
    window.delegate = self
  }

  required init?(coder: NSCoder) { nil }

  func present() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    onVisibilityChanged?(true)
  }

  func dismissForVisualDebugging() {
    window?.orderOut(nil)
    onVisibilityChanged?(false)
  }

  func windowDidBecomeKey(_ notification: Notification) { onVisibilityChanged?(true) }
  func windowWillClose(_ notification: Notification) { onVisibilityChanged?(false) }
}

private struct WorkflowIDEView: View {
  @Bindable var model: WorkflowIDEModel
  @State private var splitVisibility: NavigationSplitViewVisibility = .all
  @State private var renameWorkflowID: UUID?
  @State private var renameText = ""

  var body: some View {
    VStack(spacing: 0) {
      NavigationSplitView(columnVisibility: $splitVisibility) {
        workflowSidebar
          .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
      } content: {
        timeline
          .navigationSplitViewColumnWidth(min: 360, ideal: 470, max: 620)
      } detail: {
        detail
      }
      Divider()
      statusBar
    }
    .navigationTitle("SuperSelector Studio")
    .toolbar { toolbar }
    .textSelection(.enabled)
    .alert(
      "Rename Trail",
      isPresented: Binding(
        get: { renameWorkflowID != nil },
        set: { if !$0 { renameWorkflowID = nil } }
      )
    ) {
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) {}
      Button("Rename") {
        if let id = renameWorkflowID { model.renameWorkflow(id, to: renameText) }
      }
      .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var workflowSidebar: some View {
    List(
      selection: Binding(
        get: { model.selectedWorkflowID },
        set: { model.selectWorkflow($0) }
      )
    ) {
      Section("Recent trails") {
        ForEach(model.log.workflows) { workflow in
          WorkflowRow(workflow: workflow)
            .tag(workflow.id)
            .contextMenu {
              Button("Rename…") {
                model.selectWorkflow(workflow.id)
                renameWorkflowID = workflow.id
                renameText = workflow.name
              }
              Button("Copy JSON") {
                model.selectWorkflow(workflow.id)
                model.copySelectedJSON()
              }
              Divider()
              Button("Delete", role: .destructive) {
                model.selectWorkflow(workflow.id)
                model.deleteSelected()
              }
            }
        }
      }
    }
    .listStyle(.sidebar)
    .overlay {
      if model.log.workflows.isEmpty {
        ContentUnavailableView(
          "No recorded trails",
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text("Click, type, or scroll in another app to record a CUA workflow."))
      }
    }
  }

  @ViewBuilder
  private var timeline: some View {
    if let workflow = model.selectedWorkflow {
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 5) {
          Text(workflow.name).font(.title2.weight(.semibold))
          Text(
            "\(workflow.breadcrumbs.count) actions · \(workflow.createdAt.formatted(date: .abbreviated, time: .standard))"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()

        WorkflowScreenshotTimeline(model: model, workflow: workflow)
        Divider()
        ScrollViewReader { proxy in
          List(
            selection: Binding(
              get: { model.selectedStepID },
              set: { model.selectStep($0) }
            )
          ) {
            ForEach(Array(workflow.breadcrumbs.enumerated()), id: \.element.id) { index, step in
              WorkflowStepRow(
                index: index,
                step: step,
                hasScreenshot: step.screenshot != nil,
                isReplayPosition: model.replayProgress == index
              ).tag(step.id).id(step.id)
            }
          }
          .listStyle(.inset)
          .onAppear { proxy.scrollTo(model.selectedStepID, anchor: .center) }
          .onChange(of: model.selectedStepID) { _, id in
            withAnimation { proxy.scrollTo(id, anchor: .center) }
          }
        }
        ReplayControlSurface(model: model, stepCount: workflow.breadcrumbs.count)
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 16)
      }
    } else {
      ContentUnavailableView("Select a workflow", systemImage: "cursorarrow.motionlines")
    }
  }

  @ViewBuilder
  private var detail: some View {
    if let workflow = model.selectedWorkflow {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if let screenshot = model.selectedStep?.screenshot,
              let data = model.screenshotData(for: screenshot.assetID)
            {
              GroupBox("Selected step") {
                WorkflowScreenshotPreview(screenshot: screenshot, imageData: data)
                  .frame(minHeight: 190, idealHeight: 260)
              }
            }

            GroupBox("Human-readable script") {
              ScrollView {
                Text(workflow.renderedBreadcrumbs())
                  .font(.system(.body, design: .monospaced))
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(8)
              }
              .frame(minHeight: 120, idealHeight: 180)
            }

            GroupBox("Final SuperSelector") {
              ScrollView(.horizontal) {
                Text(workflow.finalSelector)
                  .font(.system(.caption, design: .monospaced))
                  .textSelection(.enabled)
                  .padding(8)
              }
            }

            GroupBox {
              if model.editorJSON.isEmpty {
                ContentUnavailableView {
                  Label("JSON editor is unloaded", systemImage: "doc.text")
                } description: {
                  Text("Load it only when needed to keep large workflows responsive.")
                } actions: {
                  Button("Load JSON") { model.loadEditorJSON() }
                }
              } else {
                TextEditor(text: $model.editorJSON)
                  .font(.system(.caption, design: .monospaced))
                  .scrollContentBackground(.hidden)
                  .padding(6)
                  .background(.background.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
              }
            } label: {
              Text("Editable JSON")
            }
            .frame(minHeight: 180)
          }
          .padding()
        }

        Divider()
        HStack {
          Button("Apply JSON Edits", systemImage: "checkmark.circle") {
            model.applyEditorJSON()
          }
          .disabled(model.editorJSON.isEmpty)
          Spacer()
          Button("Copy", systemImage: "doc.on.doc") { model.copySelectedJSON() }
          Button("Export…", systemImage: "square.and.arrow.up") {
            model.exportSelectedFile()
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
    } else {
      ContentUnavailableView("No workflow selected", systemImage: "sidebar.right")
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button("New Trail", systemImage: "record.circle") { model.startNewTrail() }
        .disabled(model.isReplaying)
        .help("Reset the recorder, hide applications, and start from the desktop")
      Button("Import File", systemImage: "folder.badge.plus") { model.importFile() }
      Button("Import Clipboard", systemImage: "clipboard") { model.importClipboard() }
    }
    ToolbarItemGroup(placement: .primaryAction) {
      Button("GOTO", systemImage: "scope") { model.gotoSelected() }
        .disabled(model.selectedWorkflow == nil)
      Button("Replay to Step", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
        model.replayToSelected()
      }
      .disabled(model.selectedWorkflow?.breadcrumbs.isEmpty != false || model.isReplaying)
      Menu("More", systemImage: "ellipsis.circle") {
        Button("Replay Full Workflow", systemImage: "play.fill") { model.replayAll() }
        Button("Copy Selected JSON", systemImage: "doc.on.doc") { model.copySelectedJSON() }
        Button("Copy All JSON", systemImage: "doc.on.doc.fill") { model.copyAllJSON() }
        Divider()
        Button("Clear All Recent Trails", systemImage: "trash.slash", role: .destructive) {
          model.startNewTrail(clearHistory: true)
        }
        .disabled(model.log.workflows.isEmpty)
        Button("Delete Workflow", systemImage: "trash", role: .destructive) {
          model.deleteSelected()
        }
      }
    }
  }

  private var statusBar: some View {
    HStack(spacing: 8) {
      Image(systemName: model.isReplaying ? "waveform.path.ecg" : "circle.fill")
        .foregroundStyle(model.isReplaying ? Color.orange : Color.green)
      Text(model.status).lineLimit(1)
      Spacer()
      Text("ss3/e1 · mac.ax + screen.absolute")
        .foregroundStyle(.secondary)
    }
    .font(.caption)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
    .background(.bar)
  }
}

private struct WorkflowScreenshotTimeline: View {
  @Bindable var model: WorkflowIDEModel
  let workflow: SuperSelectorWorkflow

  private var steps: [(Int, SuperSelectorWorkflowStep)] {
    workflow.breadcrumbs.enumerated().filter { $0.element.screenshot != nil }
  }

  var body: some View {
    if !steps.isEmpty {
      VStack(alignment: .leading, spacing: 7) {
        Label("Screenshots", systemImage: "timeline.selection")
          .font(.caption.weight(.semibold))
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
              ForEach(steps, id: \.1.id) { index, step in
                Button {
                  model.selectStep(step.id)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    if let screenshot = step.screenshot,
                      let data = model.screenshotData(for: screenshot.assetID)
                    {
                      WorkflowScreenshotPreview(screenshot: screenshot, imageData: data)
                        .frame(width: 128, height: 72)
                    }
                    Text("\(index + 1). \(step.action.summary)")
                      .font(.caption2).lineLimit(1).frame(width: 128, alignment: .leading)
                  }
                  .padding(4)
                  .background(
                    model.selectedStepID == step.id ? Color.pink.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                  )
                }
                .buttonStyle(.plain)
                .id(step.id)
              }
            }
            .scrollTargetLayout()
          }
          .scrollIndicators(.hidden)
          .scrollTargetBehavior(.viewAligned)
          .onAppear { proxy.scrollTo(model.selectedStepID, anchor: .center) }
          .onChange(of: model.selectedStepID) { _, id in
            guard steps.contains(where: { $0.1.id == id }) else { return }
            withAnimation { proxy.scrollTo(id, anchor: .center) }
          }
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 12)
    }
  }
}

private struct WorkflowRow: View {
  let workflow: SuperSelectorWorkflow

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "point.3.connected.trianglepath.dotted")
        .font(.title3).foregroundStyle(.pink)
      VStack(alignment: .leading, spacing: 3) {
        Text(workflow.name).font(.headline).lineLimit(1)
        Text(
          "\(workflow.breadcrumbs.count) steps · \(workflow.createdAt.formatted(date: .omitted, time: .standard))"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct WorkflowStepRow: View {
  let index: Int
  let step: SuperSelectorWorkflowStep
  let hasScreenshot: Bool
  let isReplayPosition: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      ZStack {
        Circle().fill(isReplayPosition ? Color.orange : Color.pink.opacity(0.16))
        Image(systemName: step.action.iconName)
          .foregroundStyle(isReplayPosition ? .white : .pink)
      }
      .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text("\(index + 1). \(step.action.summary)").font(.headline)
          if hasScreenshot {
            Image(systemName: "photo")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityLabel("Screenshot available")
          }
        }
        Text(step.targetPath).font(.caption).foregroundStyle(.secondary).lineLimit(3)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 5)
  }
}

private struct WorkflowScreenshotPreview: View {
  let screenshot: WorkflowScreenshot
  let imageData: Data

  var body: some View {
    GeometryReader { proxy in
      if let image = NSImage(data: imageData), image.size.width > 0, image.size.height > 0 {
        let imageRect = fittedRect(imageSize: image.size, canvasSize: proxy.size)
        ZStack(alignment: .topLeading) {
          Color.black.opacity(0.3)
          Image(nsImage: image)
            .resizable()
            .frame(width: imageRect.width, height: imageRect.height)
            .offset(x: imageRect.minX, y: imageRect.minY)
          Canvas { context, _ in
            let projection = screenshot.boxModel.projection(in: imageRect, origin: .topLeft)
            var crosshairs = Path()
            crosshairs.move(to: CGPoint(x: imageRect.minX, y: projection.pointer.y))
            crosshairs.addLine(to: CGPoint(x: imageRect.maxX, y: projection.pointer.y))
            crosshairs.move(to: CGPoint(x: projection.pointer.x, y: imageRect.minY))
            crosshairs.addLine(to: CGPoint(x: projection.pointer.x, y: imageRect.maxY))
            context.stroke(crosshairs, with: .color(.pink.opacity(0.72)), lineWidth: 1)
            if let target = projection.target {
              context.stroke(
                Path(roundedRect: target.insetBy(dx: -2, dy: -2), cornerRadius: 5),
                with: .color(.pink),
                lineWidth: 3
              )
            }
            context.fill(
              Path(
                ellipseIn: CGRect(
                  x: projection.pointer.x - 3,
                  y: projection.pointer.y - 3,
                  width: 6,
                  height: 6
                )),
              with: .color(.pink)
            )
          }
        }
      } else {
        ContentUnavailableView("Screenshot unavailable", systemImage: "photo")
      }
    }
    .background(.black.opacity(0.14))
  }

  private func fittedRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
    let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
      x: (canvasSize.width - size.width) / 2,
      y: (canvasSize.height - size.height) / 2,
      width: size.width,
      height: size.height
    )
  }
}

private struct ReplayControlSurface: View {
  @Bindable var model: WorkflowIDEModel
  let stepCount: Int

  var body: some View {
    if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: 8) {
        controls
          .padding(9)
          .glassEffect(.regular, in: .rect(cornerRadius: 16))
      }
    } else {
      controls
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  private var controls: some View {
    HStack(spacing: 10) {
      if model.isReplaying {
        Button("Stop", systemImage: "stop.fill", role: .destructive) { model.cancelReplay() }
      } else {
        Button("Replay from Reset", systemImage: "play.fill") { model.replayAll() }
        Button("To Selected", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
          model.replayToSelected()
        }
      }
      Spacer()
      Image(systemName: "hare")
      Slider(value: $model.stepDelay, in: 0.2...2.0)
        .frame(width: 110)
        .help("How long each replay target stays highlighted before its action")
      Image(systemName: "tortoise")
      Text("\(stepCount) steps").foregroundStyle(.secondary)
    }
    .buttonStyle(.bordered)
  }
}

extension SuperSelectorWorkflow {
  func renderedBreadcrumbs(through index: Int? = nil) -> String {
    let steps = index.map { Array(breadcrumbs.prefix(through: max(0, $0))) } ?? breadcrumbs
    return steps.map { "\($0.targetPath), \($0.action.breadcrumbText)" }
      .joined(separator: "\n")
  }
}

extension SuperSelectorWorkflowAction {
  var summary: String {
    switch kind {
    case .hover: return "Move pointer"
    case .click: return "\((button ?? "left").capitalized) click"
    case .scroll: return String(format: "Scroll Δx %.1f, Δy %.1f", deltaX ?? 0, deltaY ?? 0)
    case .type: return "Type \(value.map(BreadcrumbRenderer.quoted) ?? "text")"
    case .key: return "Press \(value ?? "key")"
    }
  }

  var breadcrumbText: String {
    let point = offset.map { "offset: x=\(Int($0.x.rounded())),y=\(Int($0.y.rounded()))" }
    switch kind {
    case .hover: return "[Mouse: Hover > \(point ?? "offset: x=0,y=0")]"
    case .click:
      return "[Mouse: \((button ?? "left").capitalized) Click > \(point ?? "offset: x=0,y=0")]"
    case .scroll:
      return "[Mouse: Scroll > \(point ?? "offset: x=0,y=0") > dx=\(deltaX ?? 0),dy=\(deltaY ?? 0)]"
    case .type: return "[Keyboard: Type > \(BreadcrumbRenderer.quoted(value ?? ""))]"
    case .key: return "[Keyboard: Key > \(value ?? "")]"
    }
  }

  var iconName: String {
    switch kind {
    case .hover: return "cursorarrow.motionlines"
    case .click: return "cursorarrow.click"
    case .scroll: return "scroll"
    case .type: return "keyboard"
    case .key: return "command"
    }
  }
}

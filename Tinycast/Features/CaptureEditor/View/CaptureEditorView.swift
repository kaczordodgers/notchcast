import SwiftUI

struct CaptureEditorView: View {
    @Bindable var document: CaptureEditorDocument
    let image: CaptureEditorImage
    let coordinator: CaptureEditorCoordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            HStack {
                Button(String(localized: "Close", table: "Notchcast")) { coordinator.close() }
                    .buttonStyle(.modalAction(.cancel, fillsWidth: false))
                Spacer()
                BarButton(action: document.undo) { SymbolImage(name: "arrow.uturn.backward", size: metrics.size.barBrandIcon) }
                    .disabled(!document.canUndo)
                    .accessibilityLabel(String(localized: "Undo", table: "Notchcast"))
                BarButton(action: document.redo) { SymbolImage(name: "arrow.uturn.forward", size: metrics.size.barBrandIcon) }
                    .disabled(!document.canRedo)
                    .accessibilityLabel(String(localized: "Redo", table: "Notchcast"))
                Button(String(localized: "Copy", table: "Notchcast")) { coordinator.requestCopy() }
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
            }
            HStack(spacing: metrics.spacing.md) {
                VStack(spacing: metrics.spacing.sm) {
                    ForEach(CaptureEditorTool.allCases, id: \.self) { tool in
                        BarButton(isSelected: document.tool == tool, action: { document.pick(tool) }) {
                            Text(tool.title)
                        }.accessibilityLabel(tool.title)
                            .accessibilityAddTraits(document.tool == tool ? .isSelected : [])
                    }
                    Spacer()
                    ForEach(CaptureEditorMark.Color.allCases, id: \.self) { color in
                        BarButton(isSelected: document.color == color, action: { document.pick(color) }) {
                            Text(color.title)
                        }.accessibilityLabel(color.title)
                            .accessibilityAddTraits(document.color == color ? .isSelected : [])
                    }
                }
                CaptureEditorCanvas(document: document, image: image)
            }
        }
        .padding(metrics.spacing.lg)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }

}

private struct CaptureEditorCanvas: View {
    @Bindable var document: CaptureEditorDocument
    let image: CaptureEditorImage
    @State private var preview: NSImage?
    @State private var dragging = false
    @FocusState private var editingText: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / image.points.width, geometry.size.height / image.points.height)
            ZStack(alignment: .topLeading) {
                Image(nsImage: preview ?? NSImage(cgImage: image.pixels, size: image.points))
                    .resizable()
                    .accessibilityLabel(String(localized: "Capture Editor", table: "Notchcast"))
                if document.textEdit != nil {
                    TextField(String(localized: "Text", table: "Notchcast"), text: Binding(
                        get: { document.textEdit?.string ?? "" },
                        set: { document.textEdit?.string = $0 }))
                        .focused($editingText)
                        .onAppear { editingText = true }
                        .onSubmit { document.commitText() }
                        .frame(width: max(1, image.points.width - (document.textEdit?.origin.x ?? 0)) * scale)
                        .offset(x: (document.textEdit?.origin.x ?? 0) * scale,
                                y: (document.textEdit?.origin.y ?? 0) * scale)
                }
            }
            .frame(width: image.points.width * scale, height: image.points.height * scale)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if !dragging {
                    document.pressed(at: CGPoint(x: value.startLocation.x / scale,
                        y: value.startLocation.y / scale), slack: 6 / scale)
                    dragging = true
                }
                document.dragged(to: CGPoint(x: value.location.x / scale, y: value.location.y / scale))
            }.onEnded { _ in document.released(); dragging = false })
        }
        .task(id: document.marks) {
            do {
                let png = try await CaptureEditorRender.png(image, marks: document.marks)
                try Task.checkCancellation()
                preview = NSImage(data: png)
            } catch is CancellationError {
            } catch {
                preview = nil
            }
        }
    }
}

private extension CaptureEditorTool {
    var title: String {
        switch self {
        case .arrow: String(localized: "Arrow", table: "Notchcast")
        case .text: String(localized: "Text", table: "Notchcast")
        case .rectangle: String(localized: "Rectangle", table: "Notchcast")
        case .ellipse: String(localized: "Ellipse", table: "Notchcast")
        case .blur: String(localized: "Blur", table: "Notchcast")
        }
    }
}

private extension CaptureEditorMark.Color {
    var title: String {
        switch self {
        case .red: String(localized: "Red", table: "Notchcast")
        case .yellow: String(localized: "Yellow", table: "Notchcast")
        case .green: String(localized: "Green", table: "Notchcast")
        case .blue: String(localized: "Blue", table: "Notchcast")
        case .white: String(localized: "White", table: "Notchcast")
        }
    }
}

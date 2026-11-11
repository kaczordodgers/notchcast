# Markdown Quick Look

The `MarkdownPreview` target embeds a sandboxed Quick Look view extension in Notchcast. Its identifier follows the app's active channel (`$(TINYCAST_BUNDLE_IDENTIFIER).markdown-preview`), so Debug and Release stay separate. macOS manages extension enablement in System Settings → General → Login Items & Extensions → Quick Look.

The extension accepts the system Markdown type (`net.daringfireball.markdown`). It reuses Notes' parser, text attributes, typography and TextKit layout fragments in forced Dark appearance. No JavaScript, Mermaid, HTML renderer, remote images or external resources are loaded. Mermaid fences remain code, as the catalogue's cut requires. No preview writes to the source file.

Files must be regular local files, valid UTF-8 and at most 1 MiB. A UTF-8 BOM is accepted. File reading and parsing run off the main actor, honor cancellation and pass errors to Quick Look. A replacement preparation cannot install an older result. The native read-only text view uses the existing Notes styling without adding design tokens or a custom surface.

`QuickLookCoordinator.shared.previewOnSpace(fileURL:selectedByArrowKeys:hasModifiers:isRepeat:isComposing:dismissLauncher:)` is the plain action API for a future launcher host. The caller supplies the selected file and whether arrow navigation selected it; typing or changing the result list must reset that selection flag. Ordinary typed spaces, modified keys, repeats and IME composition are left alone. A handled action dismisses the launcher before publishing `request`. Each request has a unique identity; `dismissPreview(_:)` ignores an older host's close event. Disabling the switch clears the request through the module lifecycle.

The Space switch defaults on, belongs to the existing Launcher settings group and works independently of Island. Main has no Extras section, so the automatic settings list supplies its row. The native extension's enablement is separate from this switch; it does not share app defaults or require an app group.

Left for the look: connect launcher key handling, consume requests in a native `QLPreviewPanel` host, and add an extension-management row when the Extras section lands. QuickLookUI's NSObject responder-control callbacks are nonisolated in the installed SDK; the host must preserve their synchronous ordering without adding `MainActor.assumeIsolated`. No launcher commands or deep links are registered.

Verification: `./Scripts/run-tests.sh nc-MarkdownQuickLook-engine-test` covers the Space gate, request lifetime, preferences and bounded file reading in temporary directories. `./Scripts/run-tests.sh nc-MarkdownQuickLook-extension-test` compiles the extension implementation and verifies native attributed content without registering an extension or opening a panel. A signed installed Finder preview remains a separate integration check.

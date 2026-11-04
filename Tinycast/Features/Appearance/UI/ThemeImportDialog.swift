import Foundation

enum ThemeImportDialog {
    static func request(for theme: AppearanceThemeImport) -> DialogRequest {
        DialogRequest(
            title: theme.title, message: theme.message, symbol: "paintpalette",
            actions: [
                DialogAction(title: AppearanceThemeImport.useThemeTitle),
                DialogAction(title: AppearanceThemeImport.justAddTitle),
                DialogAction(title: AppearanceThemeImport.cancelTitle, role: .cancel)
            ], defaultIndex: 0, cancelIndex: 2)
    }
}

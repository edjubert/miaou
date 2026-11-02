import AppIntents

enum MiaouWidgetRefreshRouter {
    @MainActor static var refresh: (() -> Void)?
}

struct RefreshMiaouIntent: AppIntent {
    static var title = LocalizedStringResource("widget.refresh.title", defaultValue: "Refresh Miaou")
    static var openAppWhenRun = true
    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }
    #endif

    @MainActor func perform() async throws -> some IntentResult {
        guard let refresh = MiaouWidgetRefreshRouter.refresh else {
            throw RefreshFailure()
        }
        refresh()
        return .result()
    }
}

#if !MIAOU_WIDGET
extension RefreshMiaouIntent: ForegroundContinuableIntent {}
#endif

private struct RefreshFailure: LocalizedError {
    var errorDescription: String? { L10n.t("widget.open_app") }
}

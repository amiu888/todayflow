#if canImport(AppKit)
import AppKit
import Testing
import TodayFlowCore
import TodayFlowMac
import TodayFlowRecognition

struct CaptureWindowControllerTests {
    @MainActor
    private func makeController() -> CaptureWindowController {
        let environment = AppEnvironment(
            workItems: InMemoryWorkItemRepository(),
            links: InMemoryLinkRepository(),
            attachments: InMemoryAttachmentRepository(),
            settings: InMemorySettingRepository(),
            keychain: InMemoryKeychainStore(),
            pipeline: .standard
        )
        return CaptureWindowController(environment: environment)
    }

    @Test @MainActor
    func present_showsTheCapturePanel_andDismissHidesIt() {
        let controller = makeController()
        #expect(!controller.isPresenting)

        controller.present()
        #expect(controller.isPresenting)

        controller.dismiss()
        #expect(!controller.isPresenting)
    }
}
#endif

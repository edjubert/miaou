import AppKit
import Combine

enum DesktopPetSize: String, CaseIterable {
    case small = "S"
    case medium = "M"
    case large = "L"

    var width: CGFloat {
        switch self {
        case .small: return 140
        case .medium: return 200
        case .large: return 280
        }
    }

    func dimensions(for pet: BarPet) -> CGSize {
        CGSize(width: width, height: width * pet.barWindow.height / pet.barWindow.width)
    }
}

/// Movement uses a monotonic clock, independently of drawing and mouse events.
struct DesktopPetMotion {
    static let walkingSpeed: CGFloat = 42
    static let hopDuration: TimeInterval = 0.3

    private struct Hop {
        let startedAt: TimeInterval
        let startX: CGFloat
        let endX: CGFloat
        let height: CGFloat
    }

    private(set) var x: CGFloat = 0
    private(set) var direction: CGFloat = 1
    private(set) var verticalOffset: CGFloat = 0
    private(set) var isResting = true
    private var hop: Hop?
    private var wasHovered = false
    private var nextAutomaticWalk: TimeInterval?

    var isHopping: Bool { hop != nil }

    mutating func place(at x: CGFloat) {
        self.x = x
        hop = nil
        verticalOffset = 0
        isResting = true
        wasHovered = false
        nextAutomaticWalk = nil
    }

    mutating func advance(at time: TimeInterval, elapsed: TimeInterval,
                          within limits: ClosedRange<CGFloat>, pointerOnLeft: Bool?,
                          petSize: CGSize, autonomous: Bool = false,
                          restDuration: TimeInterval = PetAnimation.restDelay.lowerBound) {
        x = min(max(x, limits.lowerBound), limits.upperBound)
        if !autonomous { nextAutomaticWalk = nil }
        let hovered = pointerOnLeft != nil
        let entered = hovered && !wasHovered
        defer { wasHovered = hovered }
        if entered, hop == nil, let pointerOnLeft {
            direction = pointerOnLeft ? 1 : -1
            let room = direction > 0 ? limits.upperBound - x : x - limits.lowerBound
            let otherRoom = limits.upperBound - limits.lowerBound - room
            // Near an edge, land inward instead of attempting a hop off-screen.
            if room < petSize.width && otherRoom > room { direction *= -1 }
            let target = min(max(x + direction * petSize.width, limits.lowerBound),
                             limits.upperBound)
            isResting = false
            nextAutomaticWalk = nil
            hop = Hop(startedAt: time, startX: x, endX: target, height: petSize.height * 0.5)
        }
        if let hop {
            let progress = CGFloat(min(max((time - hop.startedAt) / Self.hopDuration, 0), 1))
            x = min(max(hop.startX + (hop.endX - hop.startX) * progress,
                        limits.lowerBound), limits.upperBound)
            verticalOffset = 4 * hop.height * progress * (1 - progress)
            guard time >= hop.startedAt + Self.hopDuration else { return }
            self.hop = nil
            verticalOffset = 0
            // Finish at the landing position, then resume walking on the next tick.
            return
        }
        if isResting && autonomous && time >= (nextAutomaticWalk ?? time) {
            isResting = false
            nextAutomaticWalk = nil
        }
        guard !isResting else { return }
        guard limits.lowerBound < limits.upperBound else {
            isResting = true
            return
        }
        let next = x + direction * Self.walkingSpeed * min(max(elapsed, 0), 0.1)
        x = min(max(next, limits.lowerBound), limits.upperBound)
        if (direction < 0 && next <= limits.lowerBound) ||
            (direction > 0 && next >= limits.upperBound) {
            direction *= -1
            isResting = true
            nextAutomaticWalk = autonomous ? time + restDuration : nil
        }
    }
}

/// A separate, non-activating window lets the pet cross the desktop
/// without a widget background or an invisible rectangle eating clicks.
final class DesktopPetController {
    private let defaults = UserDefaults.standard
    private var observations: Set<AnyCancellable> = []
    private var panel: DesktopPetPanel?
    private var artwork: DesktopPetView?
    private var speechPanel: DesktopPetPanel?
    private var speechView: DesktopPetSpeechView?
    private let speechSource = DesktopPetSpeechSource()
    private var speechPresentation = DesktopPetSpeechPresentation()
    private var speechSessions = DesktopPetSpeechSessions()
    private var nextSpeechPoll: TimeInterval = 0
    private var timer: Timer?
    private var pet: BarPet = .chaton
    private var sizeClass: DesktopPetSize = .medium
    private var motion = DesktopPetMotion()
    private var previousTime: TimeInterval = 0

    func start() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateSettings() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.placeOnScreen() }
            .store(in: &observations)
        AppModel.shared.$dashboard
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateSettings() }
            .store(in: &observations)
        updateSettings()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        artwork = nil
        speechPanel?.close()
        speechPanel = nil
        speechView = nil
        speechPresentation.hide()
        speechSessions.reset()
        observations.removeAll()
    }

    private var selectedPet: BarPet {
        let icon = BarIconStyle(rawValue: defaults.string(forKey: "barIcon") ?? "")
        switch icon {
        case .chonk: return .chonk
        case .chaton: return AppModel.shared.isChonkModel ? .chonk : .chaton
        default: return .chaton
        }
    }

    private func updateSettings() {
        guard defaults.bool(forKey: "desktopPetEnabled") else {
            timer?.invalidate()
            timer = nil
            panel?.close()
            panel = nil
            artwork = nil
            speechPanel?.orderOut(nil)
            speechPresentation.hide()
            speechSessions.reset()
            nextSpeechPoll = 0
            return
        }
        let selection = selectedPet
        let selectedSize = DesktopPetSize(
            rawValue: defaults.string(forKey: "desktopPetSize") ?? ""
        ) ?? .medium
        if panel != nil && pet == selection && sizeClass == selectedSize { return }
        pet = selection
        sizeClass = selectedSize
        let size = sizeClass.dimensions(for: pet)
        let view = DesktopPetView(pet: pet, size: size)
        if let panel {
            // Model and size changes preserve the current trip to the edge.
            panel.contentView = view
            panel.setContentSize(size)
            artwork = view
            tick()
            return
        }
        timer?.invalidate()
        let window = DesktopPetPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("miaou-desktop-pet")
        window.title = L10n.t("desktopPet.headline")
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.animationBehavior = .none
        window.contentView = view
        artwork = view
        panel = window
        motion = DesktopPetMotion()
        previousTime = ProcessInfo.processInfo.systemUptime
        placeOnScreen(reset: true)
        tick()
        window.orderFrontRegardless()
        let animation = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
        timer = animation
        RunLoop.main.add(animation, forMode: .common)
    }

    private func placeOnScreen(reset: Bool = false) {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 0)
        let maxX = max(area.minX, area.maxX - panel.frame.width)
        let x = reset ? area.minX + (maxX - area.minX) * 0.2 :
            min(max(motion.x, area.minX), maxX)
        motion.place(at: x)
        panel.setFrameOrigin(CGPoint(x: motion.x, y: area.minY + 4))
    }

    private func tick() {
        guard let panel, let artwork, let screen = NSScreen.screens.first else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(max(now - previousTime, 0), 0.1)
        previousTime = now
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 0)
        let maxX = max(area.minX, area.maxX - panel.frame.width)
        // Poll the pointer without capturing mouse events: clicks continue
        // to pass through the companion to the desktop or window below.
        let pointer = NSEvent.mouseLocation
        let localPointer = CGPoint(x: pointer.x - panel.frame.minX,
                                   y: pointer.y - panel.frame.minY)
        let hovered = panel.frame.contains(pointer) && artwork.containsPet(at: localPointer)
        let animationMode = ChatonAnimationMode(
            rawValue: defaults.string(forKey: "desktopPetAnimation") ?? ""
        ) ?? .session
        let autonomous = animationMode == .always || AppModel.shared.hasLiveSessions
        motion.advance(at: now, elapsed: elapsed, within: area.minX...maxX,
                       pointerOnLeft: hovered ? localPointer.x < panel.frame.width / 2 : nil,
                       petSize: panel.frame.size, autonomous: autonomous,
                       restDuration: .random(in: PetAnimation.restDelay))
        let frame: Int
        var elevation = motion.verticalOffset
        if motion.isResting {
            frame = pet.restFrame
        } else {
            frame = artwork.walkFrame(at: now)
            if !motion.isHopping {
                elevation += CGFloat(abs(sin(now * .pi / 0.48))) * 1.5
            }
        }
        let scale = screen.backingScaleFactor
        panel.setFrameOrigin(CGPoint(x: (motion.x * scale).rounded() / scale,
                                     y: ((area.minY + 4 + elevation) * scale).rounded() / scale))
        let colorDuringMovement = defaults.object(forKey: "desktopPetColorDuringSession") as? Bool ?? true
        let colored = colorDuringMovement && !motion.isResting
        let glassTransparency = defaults.object(forKey: "desktopPetGlassTransparency") as? Double ?? 0
        artwork.show(frame: frame, mirrored: motion.direction < 0,
                     transparent: hovered, colored: colored, glassTransparency: glassTransparency)
        updateSpeech(at: now)
    }

    private func updateSpeech(at now: TimeInterval) {
        guard defaults.bool(forKey: "desktopPetSpeechEnabled") else {
            speechPanel?.orderOut(nil)
            speechPresentation.hide()
            speechSessions.reset()
            nextSpeechPoll = 0
            return
        }
        let sessions = speechSessions.sessionsToRead(
            active: AppModel.shared.dashboard?.liveSessions ?? [], at: now
        )
        if now >= nextSpeechPoll {
            nextSpeechPoll = now + 2
            speechSource.refresh(sessions: sessions) { [weak self] messages in
                guard let self, self.defaults.bool(forKey: "desktopPetSpeechEnabled") else { return }
                let time = ProcessInfo.processInfo.systemUptime
                let eligible = messages.filter { self.speechSessions.contains($0.sessionID, at: time) }
                self.speechPresentation.receive(eligible, at: time)
            }
        }
        guard let message = speechPresentation.visibleMessage(at: now),
              let panel, let screen = NSScreen.screens.first else {
            speechPanel?.orderOut(nil)
            return
        }
        let frame = DesktopPetSpeechView.frame(above: panel.frame, within: screen.visibleFrame)
        if speechPanel == nil {
            let bubble = DesktopPetPanel(contentRect: frame,
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
            bubble.isReleasedWhenClosed = false
            bubble.isOpaque = false
            bubble.backgroundColor = .clear
            bubble.hasShadow = true
            bubble.ignoresMouseEvents = true
            bubble.hidesOnDeactivate = false
            bubble.level = .floating
            bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            bubble.animationBehavior = .none
            bubble.identifier = NSUserInterfaceItemIdentifier("miaou-desktop-speech")
            bubble.title = L10n.t("desktopPet.speech")
            let view = DesktopPetSpeechView()
            bubble.contentView = view
            speechPanel = bubble
            speechView = view
        }
        speechPanel?.setFrame(frame, display: false)
        speechView?.tailX = panel.frame.midX - frame.minX
        let glassTransparency = defaults.object(forKey: "desktopPetGlassTransparency") as? Double ?? 0
        speechView?.show(message, glassTransparency: glassTransparency)
        if speechPanel?.isVisible == false { speechPanel?.orderFrontRegardless() }
    }
}

private final class DesktopPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The companion and its speech bubble use the same native backdrop.
enum DesktopPetGlass {
    static func makeView() -> NSView {
        if #available(macOS 26.0, *) {
            let effect = NSGlassEffectView()
            effect.style = .clear
            effect.cornerRadius = 0
            return effect
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            return effect
        }
    }

    static func apply(transparency: Double, hidden: Bool = false, to view: NSView) {
        let value = transparency.isFinite ? min(max(transparency, 0), 1) : 0
        let alpha = CGFloat(1 - value)
        if view.alphaValue != alpha { view.alphaValue = alpha }
        view.isHidden = hidden || value == 1
    }
}

/// Cache every pose once. Only window position updates at 30 fps;
/// the colored dots and glass mask change at the pet's 0.16 s cadence.
final class DesktopPetView: NSView {
    private struct Pose {
        let dots: [(rect: CGRect, row: Int)]
        let glass: CGPath
    }

    private let pet: BarPet
    private let poses: [Pose]
    private let walking: [Int]
    private let dots: DesktopPetDots
    private let glass: NSView
    private let mask = CAShapeLayer()
    private var shownFrame = -1
    private var shownMirrored = false

    init(pet: BarPet, size: CGSize) {
        self.pet = pet
        let frames = pet == .chonk ? Chonk.frames : Chaton.frames
        let pitch = min(size.width / pet.barWindow.width, size.height / pet.barWindow.height)
        func native(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
        }
        poses = frames.indices.map { index in
            let geometry = pet == .chonk
                ? Chonk.dotRects(frame: index, size: size)
                : Chaton.dotRects(frame: index, size: size)
            let silhouette = pet == .chonk
                ? Chonk.silhouetteRects(frame: index, size: size)
                : Chaton.silhouetteRects(frame: index, size: size)
            let path = CGMutablePath()
            for rect in silhouette {
                path.addRect(native(rect.insetBy(dx: -pitch * 0.075, dy: -pitch * 0.075)))
            }
            return Pose(dots: geometry.map { (native($0.rect), $0.row) }, glass: path)
        }
        // Raised ears distinguish awake head poses in both recorded grids.
        let ears = pet == .chonk ? [Chonk.key((17, 0)), Chonk.key((21, 0))]
                                : [Chaton.key((15, 1)), Chaton.key((19, 1))]
        walking = frames.indices.filter { index in
            let keys = Set(frames[index].map { $0.col * 32 + $0.row })
            return index > 0 && Set(ears).isSubset(of: keys)
        }
        let dotView = DesktopPetDots()
        dots = dotView
        glass = DesktopPetGlass.makeView()
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        glass.wantsLayer = true
        mask.frame = bounds
        glass.layer?.mask = mask
        dots.frame = bounds
        dots.autoresizingMask = [.width, .height]
        dots.gridHeight = pet.gridHeight
        addSubview(glass)
        // Keep colored dots outside the glass view so hiding the backdrop
        // never makes the outline disappear.
        addSubview(dots)
    }

    required init?(coder: NSCoder) { return nil }

    func walkFrame(at time: TimeInterval) -> Int {
        guard !walking.isEmpty else { return pet.restFrame }
        return walking[Int(time / PetAnimation.frameInterval) % walking.count]
    }

    func containsPet(at point: CGPoint) -> Bool {
        mask.path?.contains(point) ?? false
    }

    func show(frame: Int, mirrored: Bool, transparent: Bool = false, colored: Bool = false,
              glassTransparency: Double = 0) {
        DesktopPetGlass.apply(transparency: glassTransparency, hidden: transparent, to: glass)
        dots.colored = colored
        guard frame != shownFrame || mirrored != shownMirrored else { return }
        shownFrame = frame
        shownMirrored = mirrored
        let pose = poses[min(max(frame, 0), poses.count - 1)]
        var transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: bounds.width, ty: 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.path = mirrored ? pose.glass.copy(using: &transform) : pose.glass
        CATransaction.commit()
        dots.dots = pose.dots
        dots.mirrored = mirrored
        dots.needsDisplay = true
    }
}

private final class DesktopPetDots: NSView {
    var dots: [(rect: CGRect, row: Int)] = []
    var gridHeight = 10
    var mirrored = false
    var colored = false {
        didSet {
            if colored != oldValue { needsDisplay = true }
        }
    }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(false)
        if mirrored {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        let palette = colored ? MistralLogo.brand : MistralLogo.grayscale
        for dot in dots {
            context.setFillColor(palette[min(4, dot.row * 5 / gridHeight)].cgColor)
            context.fill(dot.rect)
        }
    }
}

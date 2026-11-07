import AppKit
import Combine

/// Movement uses a monotonic clock, independently of drawing and mouse events.
struct DesktopPetMotion {
    static let walkingSpeed: CGFloat = 42
    static let fleeingSpeed: CGFloat = 180
    private(set) var x: CGFloat = 0
    private(set) var direction: CGFloat = 1
    private(set) var restingSince: TimeInterval?
    private(set) var sleepDuration: TimeInterval = 0
    private var fleeingUntil: TimeInterval = -.infinity

    mutating func place(at x: CGFloat) {
        self.x = x
    }

    func isFleeing(at time: TimeInterval) -> Bool {
        time < fleeingUntil
    }

    mutating func advance(at time: TimeInterval, elapsed: TimeInterval,
                          within limits: ClosedRange<CGFloat>, pointerOnLeft: Bool?,
                          wakeDuration: TimeInterval,
                          chooseSleep: () -> TimeInterval = {
                              Double.random(in: PetAnimation.restDelay)
                          }) {
        x = min(max(x, limits.lowerBound), limits.upperBound)
        if let pointerOnLeft {
            // Keep the escape direction until clear of the pointer, rather
            // than turning back and forth as the outline changes pose.
            if !isFleeing(at: time) {
                direction = pointerOnLeft ? 1 : -1
            }
            if x == limits.lowerBound { direction = 1 }
            if x == limits.upperBound { direction = -1 }
            restingSince = nil
            fleeingUntil = time + 1
        }
        if let start = restingSince {
            guard time - start >= sleepDuration + wakeDuration else { return }
            restingSince = nil
        }
        guard limits.lowerBound < limits.upperBound else { return }
        let fleeing = isFleeing(at: time)
        let speed = fleeing ? Self.fleeingSpeed : Self.walkingSpeed
        let next = x + direction * speed * min(max(elapsed, 0), 0.1)
        x = min(max(next, limits.lowerBound), limits.upperBound)
        if (direction < 0 && next <= limits.lowerBound) ||
            (direction > 0 && next >= limits.upperBound) {
            direction *= -1
            if !fleeing {
                restingSince = time
                sleepDuration = chooseSleep()
            }
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
    private var timer: Timer?
    private var pet: BarPet = .chaton
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
            return
        }
        let selection = selectedPet
        if panel != nil && pet == selection { return }
        timer?.invalidate()
        panel?.close()
        pet = selection
        let size = CGSize(width: 200, height: 200 * pet.barWindow.height / pet.barWindow.width)
        let view = DesktopPetView(pet: pet, size: size)
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
        motion.advance(at: now, elapsed: elapsed, within: area.minX...maxX,
                       pointerOnLeft: hovered ? localPointer.x < panel.frame.width / 2 : nil,
                       wakeDuration: Double(pet.frameCount - 1) * PetAnimation.frameInterval)
        let frame: Int
        var bob: CGFloat = 0
        if let start = motion.restingSince {
            frame = artwork.restFrame(after: now - start, sleepDuration: motion.sleepDuration)
        } else {
            frame = artwork.walkFrame(at: now, fleeing: motion.isFleeing(at: now))
            bob = CGFloat(abs(sin(now * .pi / 0.48))) * 1.5
        }
        let scale = screen.backingScaleFactor
        panel.setFrameOrigin(CGPoint(x: (motion.x * scale).rounded() / scale, y: area.minY + 4 + bob))
        artwork.show(frame: frame, mirrored: motion.direction < 0, transparent: hovered)
    }
}

private final class DesktopPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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
    private let resting: [Int]
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
        var cycle: [Int] = []
        var frame = pet.restFrame
        for _ in 1..<pet.frameCount {
            frame = pet.nextFrame(after: frame)
            cycle.append(frame)
        }
        resting = cycle
        let dotView = DesktopPetDots()
        dots = dotView
        if #available(macOS 26.0, *) {
            let effect = NSGlassEffectView()
            effect.style = .clear
            effect.cornerRadius = 0
            glass = effect
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            glass = effect
        }
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

    func walkFrame(at time: TimeInterval, fleeing: Bool = false) -> Int {
        guard !walking.isEmpty else { return pet.restFrame }
        let interval = PetAnimation.frameInterval / (fleeing ? 2 : 1)
        return walking[Int(time / interval) % walking.count]
    }

    func restFrame(after elapsed: TimeInterval, sleepDuration: TimeInterval) -> Int {
        guard elapsed >= sleepDuration else { return pet.restFrame }
        let index = min(Int((elapsed - sleepDuration) / PetAnimation.frameInterval), resting.count - 1)
        return resting[index]
    }

    func containsPet(at point: CGPoint) -> Bool {
        mask.path?.contains(point) ?? false
    }

    func show(frame: Int, mirrored: Bool, transparent: Bool = false) {
        glass.isHidden = transparent
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
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(false)
        if mirrored {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        for dot in dots {
            context.setFillColor(MistralLogo.brand[min(4, dot.row * 5 / gridHeight)].cgColor)
            context.fill(dot.rect)
        }
    }
}

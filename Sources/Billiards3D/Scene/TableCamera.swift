import Foundation
import simd

/// A camera circling a point over the table. Its moves are eased: dragging, zooming and the views set where it heads.
/// From behind the ball it looks along the aim; over the table it takes it in whole, at an angle or from straight
/// above.
struct TableCamera {
    private struct Pose {
        var target = SIMD3<Float>(repeating: 0)
        var yaw: Float = 0
        var pitch: Float = 1
        var distance: Float = 4
        var shift: Float = 0
        var space: Float = 1
    }

    private static let minPitch: Float = 0.1
    private static let maxPitch: Float = 1.5703
    private static let overviewPitch: Float = 0.98
    private static let behindPitch: Float = 0.3
    private static let fieldOfView: Float = 0.6
    /// Of the space for the table, below which the view widens.
    private static let minAspect: Float = 1.55
    private static let ease: Float = 7

    private(set) var mode = CameraMode.overview
    private var width: Float = 1.27
    private var reach: Float = 1.45
    private var pose = Pose()
    private var goal = Pose()
    private var ball = SIMD3<Float>(repeating: 0)
    private var aimYaw: Float = 0

    /// The table's width between the cushions and how far the rails reach from its middle along its length.
    mutating func setTable(width: Float, reach: Float) {
        self.width = width
        self.reach = reach
        applyMode()
        pose = goal
    }

    mutating func setMode(_ mode: CameraMode) {
        self.mode = mode
        applyMode()
    }

    mutating func reset() {
        applyMode()
    }

    /// In the view from behind: the ball struck and the direction of the aim, looked along.
    mutating func follow(ball: SIMD3<Float>, aim: SIMD2<Float>, instant: Bool = false) {
        self.ball = ball
        if length(aim) < 1e-6 {
            return
        }
        aimYaw = atan2(-aim.x, -aim.y)
        if mode != .behind {
            return
        }
        let ahead = 0.16 * reach
        let size = length(aim)
        goal.target = ball + SIMD3(aim.x / size * ahead, 0, aim.y / size * ahead)
        goal.yaw = Self.unwrap(aimYaw, goal.yaw)
        if goal.pitch > 0.75 {
            goal.pitch = Self.behindPitch
        }
        if instant {
            pose = goal
        }
    }

    /// While the balls roll, the view from behind rises to see more of the table.
    mutating func lift() {
        if mode != .behind {
            return
        }
        goal.pitch = max(goal.pitch, 0.62)
        goal.distance = max(goal.distance * 1.3, 0.9 * reach)
        goal.target = goal.target + (SIMD3<Float>(repeating: 0) - goal.target) * 0.35
    }

    mutating func rotate(yaw: Float, pitch: Float) {
        goal.yaw += yaw
        goal.pitch = min(max(goal.pitch + pitch, Self.minPitch), Self.maxPitch)
        if mode == .top {
            mode = .overview
        }
    }

    mutating func zoom(_ steps: Float) {
        goal.distance = min(max(goal.distance * pow(0.88, steps), 0.3 * reach), 4.2 * reach)
    }

    /// The share of the window's width left for the table beside the panel: the view centers on it, and widens when
    /// it is narrow, so the whole table stays in sight.
    mutating func setSpace(_ share: Float) {
        goal.shift = (share - 1) / 2
        goal.space = share
    }

    mutating func update(_ seconds: Float) {
        let ease = 1 - exp(-seconds * Self.ease)
        pose.target = pose.target + (goal.target - pose.target) * ease
        pose.yaw += (goal.yaw - pose.yaw) * ease
        pose.pitch += (goal.pitch - pose.pitch) * ease
        // The distance eases by ratio, so that zooming feels the same near and far.
        pose.distance *= pow(goal.distance / pose.distance, ease)
        pose.shift += (goal.shift - pose.shift) * ease
        pose.space += (goal.space - pose.space) * ease
    }

    var isMoving: Bool {
        length(goal.target - pose.target) > 1e-4 || abs(goal.yaw - pose.yaw) > 1e-4 || abs(goal.pitch - pose.pitch) > 1e-4
            || abs(goal.distance / pose.distance - 1) > 1e-4 || abs(goal.shift - pose.shift) > 1e-4 || abs(goal.space - pose.space) > 1e-4
    }

    var eye: SIMD3<Float> {
        let horizontal = cos(pose.pitch)
        return pose.target + SIMD3(sin(pose.yaw) * horizontal, sin(pose.pitch), cos(pose.yaw) * horizontal) * pose.distance
    }

    var view: float4x4 {
        // Looking straight down, "up" on the screen points away from the eye's side of the table.
        let yaw = pose.yaw
        let pitch = pose.pitch
        let up = Matrix.unit(SIMD3(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch)))
        return Matrix.lookAt(eye: eye, target: pose.target, up: up)
    }

    func projection(aspect: Float) -> float4x4 {
        let widen = max(1, Self.minAspect / (aspect * pose.space))
        var projection = Matrix.perspective(fovY: 2 * atan(tan(Self.fieldOfView / 2) * widen), aspect: aspect, near: 0.01 * reach, far: 16 * reach)
        projection.columns.2.x = -2 * pose.shift // shift in normalized coordinates, which span 2
        return projection
    }

    /// The ray through a point of the window, in pixels from the top left.
    func ray(x: Float, y: Float, width: Float, height: Float) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let inverse = (projection(aspect: width / max(height, 1)) * view).inverse
        let nx = x / width * 2 - 1
        let ny = 1 - y / height * 2
        let near = Matrix.transform(SIMD3(nx, ny, 0), by: inverse)
        let far = Matrix.transform(SIMD3(nx, ny, 1), by: inverse)
        return (near, Matrix.unit(far - near))
    }

    /// A point of the scene in pixels from the window's top left; nil behind the camera.
    func toScreen(_ point: SIMD3<Float>, width: Float, height: Float) -> SIMD2<Float>? {
        let viewProjection = projection(aspect: width / max(height, 1)) * view
        let clip = viewProjection * SIMD4(point, 1)
        if clip.w <= 1e-6 {
            return nil
        }
        return SIMD2((clip.x / clip.w + 1) / 2 * width, (1 - clip.y / clip.w) / 2 * height)
    }

    // MARK: - Helpers

    private mutating func applyMode() {
        switch mode {
        case .overview:
            goal.target = SIMD3(0, 0, 0.04 * width)
            goal.yaw = Self.unwrap(0, goal.yaw)
            goal.pitch = Self.overviewPitch
            goal.distance = 2.45 * reach
        case .top:
            goal.target = SIMD3(0, 0, 0)
            goal.yaw = Self.unwrap(0, goal.yaw)
            goal.pitch = Self.maxPitch
            goal.distance = 2.3 * reach
        case .behind:
            goal.pitch = Self.behindPitch
            goal.distance = 0.42 * reach + 0.5
            follow(ball: ball, aim: SIMD2(-sin(aimYaw), -cos(aimYaw)))
        }
    }

    /// The angle nearest to `current` that points the same way as `angle`.
    private static func unwrap(_ angle: Float, _ current: Float) -> Float {
        var angle = angle
        while angle - current > Float.pi {
            angle -= 2 * Float.pi
        }
        while angle - current < -Float.pi {
            angle += 2 * Float.pi
        }
        return angle
    }
}

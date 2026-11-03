import Foundation
import Testing
import TodayFlowDesign

/// driver.md §4 animations (all respect Reduce Motion): checkmark draw-on
/// 250ms, row slides to Done, ring advances with a spring, confetti at 50% and
/// 100%. Under Reduce Motion every animation collapses to its final state.
@Suite("Motion")
struct MotionTests {
    @Test("fullMotionExposesDurations")
    func fullMotionExposesDurations() {
        let motion = Motion(preference: .full)
        #expect(motion.duration(for: .checkmark) == 0.25)
        #expect(motion.duration(for: .rowSlide) == 0.3)
        #expect(motion.duration(for: .ring) == 0.45)
        #expect(motion.duration(for: .confetti) == 1.2)
    }

    @Test("reducedMotionDisablesEveryAnimation")
    func reducedMotionDisablesEveryAnimation() {
        let motion = Motion(preference: .reduced)
        for kind in Motion.Kind.allCases {
            #expect(motion.duration(for: kind) == nil)
            #expect(motion.spring(for: kind) == nil)
        }
    }

    @Test("ringSpringParameters")
    func ringSpringParameters() {
        let motion = Motion(preference: .full)
        let spring = motion.spring(for: .ring)
        #expect(spring?.response == 0.45)
        #expect(spring?.damping == 0.8)
    }

    @Test("nonSpringKindsHaveNoSpring")
    func nonSpringKindsHaveNoSpring() {
        let motion = Motion(preference: .full)
        for kind in Motion.Kind.allCases where kind != .ring {
            #expect(motion.spring(for: kind) == nil)
        }
    }

    @Test("equatableByPreferenceAndDurations")
    func equatableByPreferenceAndDurations() {
        #expect(Motion(preference: .full) == Motion(preference: .full))
        #expect(Motion(preference: .full) != Motion(preference: .reduced))
    }
}

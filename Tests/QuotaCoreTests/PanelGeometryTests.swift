import CoreGraphics
import Foundation
import Testing
@testable import QuotaCore

@Test func presentationSizesAreExact() {
    #expect(CompanionPresentation.collapsed.size == CGSize(width: 56, height: 56))
    #expect(CompanionPresentation.expanded.size == CGSize(width: 240, height: 156))
}

@Test func resizingPreservesNearestBottomRightEdges() {
    let visible = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    let collapsed = CGRect(x: 930, y: 20, width: 56, height: 56)
    let expanded = PanelGeometry.resizedFrame(from: collapsed, to: CompanionPresentation.expanded.size, in: visible)
    #expect(expanded.maxX == collapsed.maxX)
    #expect(expanded.minY == collapsed.minY)
    #expect(expanded.size == CGSize(width: 240, height: 156))
}

@Test func resizingPreservesNearestTopLeftEdges() {
    let visible = CGRect(x: -1_200, y: 100, width: 1_200, height: 900)
    let collapsed = CGRect(x: -1_180, y: 930, width: 56, height: 56)
    let expanded = PanelGeometry.resizedFrame(from: collapsed, to: CompanionPresentation.expanded.size, in: visible)
    #expect(expanded.minX == collapsed.minX)
    #expect(expanded.maxY == collapsed.maxY)
}

@Test func frameIsConstrainedToCurrentDisplay() {
    let visible = CGRect(x: 0, y: 24, width: 800, height: 576)
    let outside = CGRect(x: 790, y: -100, width: 280, height: 220)
    let result = PanelGeometry.constrained(outside, to: visible)
    #expect(result.maxX == visible.maxX)
    #expect(result.minY == visible.minY)
}

@Test func snappingOnlyChangesAxesWithinThreshold() {
    let visible = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    let nearRight = CGRect(x: 920, y: 300, width: 56, height: 56)
    let result = PanelGeometry.snappedFrame(nearRight, in: visible)
    #expect(result.maxX == visible.maxX - 14)
    #expect(result.minY == nearRight.minY)
}

@Test func fourPointPointerThresholdDistinguishesClickAndDrag() {
    #expect(PointerIntent.classify(delta: CGSize(width: 3, height: 2)) == .click)
    #expect(PointerIntent.classify(delta: CGSize(width: 4, height: 0)) == .drag)
    #expect(PointerIntent.classify(delta: CGSize(width: 3, height: 3)) == .drag)
}

@Test func expectedSizeValidationRejectsIntermediateFrames() {
    #expect(PanelGeometry.matches(CGSize(width: 56, height: 56), presentation: .collapsed))
    #expect(!PanelGeometry.matches(CGSize(width: 112, height: 112), presentation: .collapsed))
    #expect(!PanelGeometry.matches(CGSize(width: 176, height: 138), presentation: .expanded))
}

@Test func compactLayoutFollowsActualQuotaRowCount() {
    for count in [-1, 0, 1] {
        #expect(CompanionLayout(presentation: .expanded, windowCount: count).size == CGSize(width: 240, height: 156))
    }
    #expect(CompanionLayout(presentation: .expanded, windowCount: 2).size == CGSize(width: 240, height: 204))
    #expect(CompanionLayout(presentation: .expanded, windowCount: 3).size.height == 252)
    #expect(CompanionLayout(presentation: .collapsed, windowCount: 2).size == CGSize(width: 56, height: 56))
}

@Test func constrainedLayoutAndValidationUseTheSameExpectedSize() {
    let layout = CompanionLayout(presentation: .expanded, windowCount: 2, availableSize: CGSize(width: 220, height: 180))
    #expect(layout.size == CGSize(width: 220, height: 180))
    #expect(layout.matches(layout.size))
    #expect(!layout.matches(layout.idealSize))
    #expect(!layout.matches(CGSize(width: CGFloat.nan, height: 180)))
    #expect(!layout.matches(CGSize(width: CGFloat.infinity, height: 180)))
    #expect(layout.cornerRadius == 24)
    #expect(CompanionLayout(presentation: .collapsed, windowCount: 1).cornerRadius == 28)
}

@Test func rowCountChangesPreserveTheCurrentAnchor() {
    let visible = CGRect(x: -1200, y: 80, width: 1200, height: 800)
    for origin in [CGPoint(x: -1190, y: 90), CGPoint(x: -250, y: 90), CGPoint(x: -250, y: 670)] {
        let initial = CGRect(origin: origin, size: CompanionPresentation.expanded.size)
        let anchor = PanelGeometry.nearestAnchor(for: initial, in: visible)
        let grown = PanelGeometry.resizedFrame(from: initial, to: CompanionLayout(presentation: .expanded, windowCount: 2).size, in: visible)
        #expect(anchor.horizontal == .trailing ? grown.maxX == initial.maxX : grown.minX == initial.minX)
        #expect(anchor.vertical == .top ? grown.maxY == initial.maxY : grown.minY == initial.minY)
        #expect(PanelGeometry.resizedFrame(from: grown, to: initial.size, in: visible, preserving: anchor) == initial)
    }
}

@Test func savedCollapsedFootprintSurvivesAnExpandedRelaunch() {
    let visible = CGRect(x: 0, y: 80, width: 1400, height: 820)
    for origin in [CGPoint(x: 20, y: 100), CGPoint(x: 1320, y: 100), CGPoint(x: 1320, y: 820)] {
        let collapsed = CGRect(origin: origin, size: CompanionPresentation.collapsed.size)
        for count in [1, 2] {
            let expanded = PanelGeometry.resizedFrame(from: collapsed,
                to: CompanionLayout(presentation: .expanded, windowCount: count).size, in: visible)
            #expect(PanelGeometry.resizedFrame(from: expanded, to: collapsed.size, in: visible) == collapsed)
        }
    }
}

@Test func pluginExpansionBeforeLaunchRestoresTheSameAnchoredFrame() {
    let visible = CGRect(x: 0, y: 80, width: 2560, height: 1400)
    let layout = CompanionLayout(presentation: .expanded, windowCount: 1)
    let expanded = CGRect(x: 1188, y: 120, width: 240, height: 156)
    let saved = PanelGeometry.resizedFrame(from: expanded, to: CompanionPresentation.collapsed.size, in: visible).origin
    #expect(PanelGeometry.restoredFrame(savedCollapsedOrigin: saved, layout: layout, in: visible) == expanded)
}

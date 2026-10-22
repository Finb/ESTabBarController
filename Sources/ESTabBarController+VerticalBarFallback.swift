//
//  ESTabBarController+VerticalBarFallback.swift
//  ESTabBarController
//
//  iPhone Duo（iOS 27.1）竖屏时，UIKit 会把 TabBar 放进竖向控制栏的零高度/离屏宿主容器。
//  ESTabBar 的 item 仍会被绘制到竖栏区域，但 window.hitTest 在宿主容器处剪枝，
//  ESTabBarItemContainer 收不到触摸。这里在 window 上兜底接管竖栏点击。
//

import UIKit

internal extension ESTabBarController {

    private var verticalBarTabBar: ESTabBar? {
        return tabBar as? ESTabBar
    }

    private var verticalBarWindow: UIWindow? {
        return isViewLoaded ? view.window : nil
    }

    func updateVerticalBarTapFallbackIfNeeded() {
        updateVerticalBarHostChromeIfNeeded()
        guard isVerticalBarTapFallbackEnabled, let window = verticalBarWindow else {
            removeVerticalBarTapFallback()
            return
        }
        if let gesture = verticalBarFallbackGesture, gesture.view === window {
            return
        }
        removeVerticalBarTapFallback()
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleVerticalBarFallbackTap(_:)))
        gesture.delegate = self
        window.addGestureRecognizer(gesture)
        verticalBarFallbackGesture = gesture
    }
    
    /// 有些系统版本会把竖栏背景画在 tabBar 的宿主容器上，而不是 tabBar 自身。
    /// 竖向胶囊布局时临时清空这些祖先的背景色，退出竖向时恢复。
    private func updateVerticalBarHostChromeIfNeeded() {
        guard isVerticalBarTapFallbackActive else {
            restoreVerticalBarHostChrome()
            return
        }
        var host = tabBar.superview
        while let view = host, view !== self.view {
            if !verticalBarHostBackgrounds.contains(where: { $0.view === view }),
               let color = view.backgroundColor,
               color.cgColor.alpha > 0.01
            {
                verticalBarHostBackgrounds.append((view, color))
                view.backgroundColor = .clear
            }
            host = view.superview
        }
    }
    
    private func restoreVerticalBarHostChrome() {
        guard !verticalBarHostBackgrounds.isEmpty else {
            return
        }
        for entry in verticalBarHostBackgrounds {
            entry.view.backgroundColor = entry.color
        }
        verticalBarHostBackgrounds.removeAll()
    }

    func removeVerticalBarTapFallback() {
        if let gesture = verticalBarFallbackGesture {
            gesture.view?.removeGestureRecognizer(gesture)
        }
        verticalBarFallbackGesture = nil
    }

    private var isVerticalBarTapFallbackActive: Bool {
        guard let est = verticalBarTabBar,
              let items = est.items,
              items.contains(where: { $0 is ESTabBarItem })
        else {
            return false
        }
        return est.isVerticalLayout
            && !est.isHidden
            && est.alpha > 0.01
            && est.bounds.height > est.bounds.width + 0.5
    }

    /// 竖向栏在窗口中的可见区域。系统可能把 tabBar 放进离屏容器，转换结果无效时不接管点击。
    private func verticalBarVisibleRect(in window: UIWindow) -> CGRect? {
        guard isVerticalBarTapFallbackActive, let est = verticalBarTabBar else { return nil }
        let itemFrames = est.itemFrames.filter { $0.width > 1 && $0.height > 1 }
        guard let first = itemFrames.first else { return nil }
        let union = itemFrames.dropFirst().reduce(first) { $0.union($1) }
        let barRect = est.verticalBarCapsuleFrame ?? union
        let converted = est.convert(barRect, to: window)
        guard converted.width > 1,
              converted.height > 1,
              window.bounds.intersects(converted)
        else {
            return nil
        }
        return converted
    }

    private func verticalBarItemIndex(at point: CGPoint, in est: ESTabBar) -> Int? {
        let controllersCount = viewControllers?.count ?? est.itemFrames.count
        let count = min(est.itemFrames.count, controllersCount)
        let frames = Array(est.itemFrames.prefix(count))
        guard !frames.isEmpty else { return nil }
        if frames.allSatisfy({ $0.width > 1 && $0.height > 1 }) {
            // 相邻 item 间距或边缘也取最近的 item，避免点击死区
            return frames.enumerated()
                .min { abs($0.element.midY - point.y) < abs($1.element.midY - point.y) }?
                .offset
        }
        let height = est.bounds.height
        guard height > 0 else { return nil }
        let index = Int(point.y / (height / CGFloat(frames.count)))
        return min(max(index, 0), frames.count - 1)
    }

    private func performVerticalBarTap(at pointInWindow: CGPoint, in window: UIWindow) {
        guard let rect = verticalBarVisibleRect(in: window),
              let est = verticalBarTabBar,
              let controllers = viewControllers,
              rect.contains(pointInWindow)
        else {
            return
        }
        let pointInBar = est.convert(pointInWindow, from: window)
        guard let index = verticalBarItemIndex(at: pointInBar, in: est),
              index >= 0,
              index < controllers.count
        else {
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["ESTABB_BAR_DEBUG_LAYOUT"] == "1" {
            print("ESTabBarController vertical bar fallback tap -> index \(index)")
        }
        #endif
        didTapVerticalBarItem(at: index)
    }

    @objc private func handleVerticalBarFallbackTap(_ gesture: UITapGestureRecognizer) {
        guard let window = gesture.view as? UIWindow else { return }
        performVerticalBarTap(at: gesture.location(in: window), in: window)
    }
}

extension ESTabBarController: UIGestureRecognizerDelegate {

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldReceive touch: UITouch) -> Bool
    {
        guard gestureRecognizer === verticalBarFallbackGesture,
              let window = gestureRecognizer.view as? UIWindow,
              verticalBarWindow === window,
              presentedViewController == nil,
              let rect = verticalBarVisibleRect(in: window)
        else {
            return false
        }
        let point = touch.location(in: window)
        guard rect.contains(point) else { return false }
        // 系统能正常命中 tabBar 时不重复处理
        if let hit = window.hitTest(point, with: nil), hit === tabBar || hit.isDescendant(of: tabBar) {
            return false
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        return gestureRecognizer === verticalBarFallbackGesture || otherGestureRecognizer === verticalBarFallbackGesture
    }
}

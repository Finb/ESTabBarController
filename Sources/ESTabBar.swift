//
//  ESTabBar.swift
//
//  Created by Vincent Li on 2017/2/8.
//  Copyright (c) 2013-2020 ESTabBarController (https://github.com/eggswift/ESTabBarController)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit


/// 对原生的UITabBarItemPositioning进行扩展，通过UITabBarItemPositioning设置时，系统会自动添加insets，这使得添加背景样式的需求变得不可能实现。ESTabBarItemPositioning完全支持原有的item Position 类型，除此之外还支持完全fill模式。
///
/// - automatic: UITabBarItemPositioning.automatic
/// - fill: UITabBarItemPositioning.fill
/// - centered: UITabBarItemPositioning.centered
/// - fillExcludeSeparator: 完全fill模式，布局不覆盖tabBar顶部分割线
/// - fillIncludeSeparator: 完全fill模式，布局覆盖tabBar顶部分割线
public enum ESTabBarItemPositioning : Int {
    
    case automatic
    
    case fill
    
    case centered
    
    case fillExcludeSeparator
    
    case fillIncludeSeparator
}



/// 对UITabBarDelegate进行扩展，以支持UITabBarControllerDelegate的相关方法桥接
internal protocol ESTabBarDelegate: NSObjectProtocol {

    /// 当前item是否支持选中
    ///
    /// - Parameters:
    ///   - tabBar: tabBar
    ///   - item: 当前item
    /// - Returns: Bool
    func tabBar(_ tabBar: UITabBar, shouldSelect item: UITabBarItem) -> Bool
    
    /// 当前item是否需要被劫持
    ///
    /// - Parameters:
    ///   - tabBar: tabBar
    ///   - item: 当前item
    /// - Returns: Bool
    func tabBar(_ tabBar: UITabBar, shouldHijack item: UITabBarItem) -> Bool
    
    /// 当前item的点击被劫持
    ///
    /// - Parameters:
    ///   - tabBar: tabBar
    ///   - item: 当前item
    /// - Returns: Void
    func tabBar(_ tabBar: UITabBar, didHijack item: UITabBarItem)
}



/// ESTabBar是高度自定义的UITabBar子类，通过添加UIControl的方式实现自定义tabBarItem的效果。目前支持tabBar的大部分属性的设置，例如delegate,items,selectedImge,itemPositioning,itemWidth,itemSpacing等，以后会更加细致的优化tabBar原有属性的设置效果。
open class ESTabBar: UITabBar {

    internal weak var customDelegate: ESTabBarDelegate?
    
    /// set value > 0 to change tabbar height
    /// 设置 > 0 的值了来修改TabBar的高度
    public var tabBarHeight: CGFloat?{
        didSet{
            guard tabBarHeight ?? 0 > 0 else{
                return
            }
            setNeedsLayout()
        }
    }
    
    /// tabBar中items布局偏移量
    public var itemEdgeInsets = UIEdgeInsets.zero
    /// 是否设置为自定义布局方式，默认为空。如果为空，则通过itemPositioning属性来设置。如果不为空则忽略itemPositioning,所以当tabBar的itemCustomPositioning属性不为空时，如果想改变布局规则，请设置此属性而非itemPositioning。
    public var itemCustomPositioning: ESTabBarItemPositioning? {
        didSet {
            if let itemCustomPositioning = itemCustomPositioning {
                switch itemCustomPositioning {
                case .fill:
                    itemPositioning = .fill
                case .automatic:
                    itemPositioning = .automatic
                case .centered:
                    itemPositioning = .centered
                default:
                    break
                }
            }
            self.reload()
        }
    }
    /// tabBar自定义item的容器view
    internal var containers = [ESTabBarItemContainer]()
    /// 缓存当前tabBarController用来判断是否存在"More"Tab
    internal weak var tabBarController: UITabBarController?
    /// 当前是否处于竖向控制栏布局（iPhone Duo 等设备的 shared bar）。
    /// 只读；每次 layout 时自动更新。
    public private(set) var isVerticalLayout: Bool = false
    /// item 容器的 frame（tabBar 坐标）。
    /// iOS 27.1 Duo 上系统可能把 tabBar 放到零高度容器中导致触摸无法路由，调用方可据此做兜底命中。
    public var itemFrames: [CGRect] {
        containers.map { $0.frame }
    }
    #if DEBUG
    private var lastDebugLayoutDescription: String?
    #endif
    /// 自定义'More'按钮样式，继承自ESTabBarItemContentView
    open var moreContentView: ESTabBarItemContentView? = ESTabBarItemMoreContentView.init() {
        didSet { self.reload() }
    }
    
    open override var items: [UITabBarItem]? {
        didSet {
            self.reload()
        }
    }
    
    open var isEditing: Bool = false {
        didSet {
            if oldValue != isEditing {
                self.updateLayout()
            }
        }
    }
    
    open override func setItems(_ items: [UITabBarItem]?, animated: Bool) {
        super.setItems(items, animated: animated)
        self.reload()
    }
    
    open override func beginCustomizingItems(_ items: [UITabBarItem]) {
        ESTabBarController.printError("beginCustomizingItems(_:) is unsupported in ESTabBar.")
        super.beginCustomizingItems(items)
    }
    
    open override func endCustomizing(animated: Bool) -> Bool {
        ESTabBarController.printError("endCustomizing(_:) is unsupported in ESTabBar.")
        return super.endCustomizing(animated: animated)
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        self.applyLiquidGlassCompatibilityIfNeeded()
        self.updateLayout()
        #if DEBUG
        self.debugLogLayoutIfNeeded()
        #endif
    }
    
    open override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        if #available(iOS 26.0, *), hasCustomItems {
            self.suppressLiquidGlassChrome(in: subview)
            self.disableContinuousSelectionGestures(in: subview)
        }
    }
    
    open override func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        super.addGestureRecognizer(gestureRecognizer)
        if #available(iOS 26.0, *), hasCustomItems, ESTabBar.isContinuousSelectionGestureRecognizer(gestureRecognizer) {
            gestureRecognizer.isEnabled = false
        }
    }
    
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let defaultSize = super.sizeThatFits(size)
        if let tabBarHeight, tabBarHeight > 0{
            return CGSize(width: defaultSize.width, height: tabBarHeight)
        }
        return defaultSize
    }
    
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var b = super.point(inside: point, with: event)
        if !b {
            for container in containers {
                if container.point(inside: CGPoint.init(x: point.x - container.frame.origin.x, y: point.y - container.frame.origin.y), with: event) {
                    b = true
                }
            }
        }
        return b
    }
    
    private var hasCustomItems: Bool {
        return items?.contains(where: { $0 is ESTabBarItem }) ?? false
    }
    
    private func applyLiquidGlassCompatibilityIfNeeded() {
        if #available(iOS 26.0, *), hasCustomItems {
            self.suppressLiquidGlassChrome(in: self)
            self.disableContinuousSelectionGestures(in: self)
            for container in containers {
                self.bringSubviewToFront(container)
            }
        }
    }
    
    private func suppressLiquidGlassChrome(in view: UIView) {
        if ESTabBar.isLiquidGlassChromeView(view) {
            view.isHidden = true
        }
        for subview in view.subviews {
            self.suppressLiquidGlassChrome(in: subview)
        }
    }
    
    private func disableContinuousSelectionGestures(in view: UIView) {
        for gestureRecognizer in view.gestureRecognizers ?? [] {
            if ESTabBar.isContinuousSelectionGestureRecognizer(gestureRecognizer) {
                gestureRecognizer.isEnabled = false
            }
        }
        for subview in view.subviews {
            self.disableContinuousSelectionGestures(in: subview)
        }
    }
    
    private static func isLiquidGlassChromeView(_ view: UIView) -> Bool {
        let className = NSStringFromClass(type(of: view))
        guard className.contains("UITabBar") else {
            return false
        }
        return className.hasSuffix("PlatterView") || className.hasSuffix("GlassBackground")
    }
    
    private static func isContinuousSelectionGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return NSStringFromClass(type(of: gestureRecognizer)).hasSuffix("_UIContinuousSelectionGestureRecognizer")
    }
    
}

internal extension ESTabBar /* Layout */ {
    
    func updateLayout() {
        guard let tabBarItems = self.items else {
            ESTabBarController.printError("empty items")
            return
        }
        
        let vertical = updateVerticalLayoutState()
        let tabBarButtons = systemTabBarButtons()
        
        if isCustomizing {
            for (idx, _) in tabBarItems.enumerated() where idx < tabBarButtons.count {
                tabBarButtons[idx].isHidden = false
            }
            moreContentView?.isHidden = true
            for container in containers {
                container.isHidden = true
            }
            return
        }
        
        for container in containers {
            container.isHidden = false
        }
        
        if vertical {
            // Native-only usage must keep the system tab bar untouched.
            if hasCustomItems {
                layoutContainersWithVerticalControlBar(tabBarItems: tabBarItems, tabBarButtons: tabBarButtons)
            }
            return
        }
        
        let orderedTabBarButtons = tabBarButtons.sorted { (view1, view2) -> Bool in
            let frame1 = self.convert(view1.bounds, from: view1)
            let frame2 = self.convert(view2.bounds, from: view2)
            return frame1.origin.x < frame2.origin.x
        }
        let usesFlatLayout = self.usesFlatLayout()
        
        if usesFlatLayout {
            for tabBarButton in orderedTabBarButtons {
                tabBarButton.isHidden = true
            }
        } else {
            for (idx, item) in tabBarItems.enumerated() {
                guard idx < orderedTabBarButtons.count else {
                    continue
                }
                let isCustomItem = item is ESTabBarItem || (isMoreItem(idx) && moreContentView != nil)
                orderedTabBarButtons[idx].isHidden = isCustomItem
            }
        }
        
        if let itemCustomPositioning = itemCustomPositioning {
            switch itemCustomPositioning {
            case .fillIncludeSeparator, .fillExcludeSeparator:
                self.layoutContainers(withCustomPositioning: itemCustomPositioning)
                return
            default:
                break
            }
        }
        
        if !usesFlatLayout, self.canUseSystemLayout(tabBarButtons: orderedTabBarButtons) {
            for (idx, container) in containers.enumerated() {
                container.frame = self.convert(orderedTabBarButtons[idx].bounds, from: orderedTabBarButtons[idx])
            }
            return
        }
        
        self.layoutContainersWithFlatStyle()
    }
    
    private func updateVerticalLayoutState() -> Bool {
        let vertical = bounds.height > bounds.width + 0.5
        if vertical != isVerticalLayout {
            isVerticalLayout = vertical
            applyVerticalLayoutState()
        }
        return vertical
    }
    
    private func applyVerticalLayoutState() {
        guard let tabBarItems = items else {
            return
        }
        for item in tabBarItems {
            if let item = item as? ESTabBarItem {
                item.contentView.isVerticalLayout = isVerticalLayout
            }
        }
        moreContentView?.isVerticalLayout = isVerticalLayout
    }
    
    private func layoutContainersWithVerticalControlBar(tabBarItems: [UITabBarItem], tabBarButtons: [UIView]) {
        for tabBarButton in tabBarButtons {
            tabBarButton.isHidden = true
        }
        
        if let frames = verticalItemFrames(for: tabBarItems, tabBarButtons: tabBarButtons) {
            for (idx, container) in containers.enumerated() where idx < frames.count {
                container.frame = frames[idx]
            }
            return
        }
        
        layoutContainersWithVerticalFallback()
    }
    
    private func verticalItemFrames(for tabBarItems: [UITabBarItem], tabBarButtons: [UIView]) -> [CGRect]? {
        guard !tabBarButtons.isEmpty else {
            return nil
        }
        let pairs = tabBarButtons.compactMap { (button: UIView) -> (UIView, CGRect)? in
            let frame = self.convert(button.bounds, from: button)
            guard !frame.isEmpty, self.bounds.intersects(frame) else {
                return nil
            }
            return (button, frame)
        }
        guard pairs.count >= containers.count else {
            return nil
        }
        
        let orderedPairs: [(UIView, CGRect)]
        if let matched = matchSystemButtonsToItems(pairs, items: tabBarItems), matched.count >= containers.count {
            orderedPairs = matched
        } else {
            orderedPairs = pairs.sorted { $0.1.origin.y < $1.1.origin.y }
        }
        return Array(orderedPairs.prefix(containers.count).map { $0.1 })
    }
    
    private func matchSystemButtonsToItems(_ pairs: [(UIView, CGRect)], items: [UITabBarItem]) -> [(UIView, CGRect)]? {
        var matched: [(Int, UIView, CGRect)] = []
        for (button, frame) in pairs {
            if let index = itemIndex(for: button, items: items) {
                matched.append((index, button, frame))
            }
        }
        guard matched.count == pairs.count, matched.count >= items.count else {
            return nil
        }
        guard Set(matched.map { $0.0 }).count == matched.count else {
            return nil
        }
        return matched.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
    }
    
    private func itemIndex(for button: UIView, items: [UITabBarItem]) -> Int? {
        let labels = [button.accessibilityIdentifier, button.accessibilityLabel].compactMap { $0 }.filter { !$0.isEmpty }
        guard !labels.isEmpty else {
            return nil
        }
        for (idx, item) in items.enumerated() {
            if let identifier = item.accessibilityIdentifier, !identifier.isEmpty, labels.contains(identifier) {
                return idx
            }
            if let title = item.title, !title.isEmpty, labels.contains(where: { $0.contains(title) }) {
                return idx
            }
        }
        return nil
    }
    
    private func layoutContainersWithVerticalFallback() {
        guard !containers.isEmpty else {
            return
        }
        let insets = layoutSafeAreaInsets
        let verticalSafeInsets = insets.top + insets.bottom
        let insetTop = verticalSafeInsets < bounds.height ? insets.top : 0
        let insetBottom = verticalSafeInsets < bounds.height ? insets.bottom : 0
        let top = insetTop + itemEdgeInsets.top
        let bottom = insetBottom + itemEdgeInsets.bottom
        let height = max(0, bounds.height - top - bottom)
        guard height > 0 else {
            return
        }
        
        let left: CGFloat
        let width: CGFloat
        if let column = verticalBarColumnRect() {
            // The system vertical bar is a narrow column near the window edge. Center the
            // items in that column so they line up with the status bar icons.
            left = column.minX
            width = column.width
        } else {
            // The vertical bar is already positioned inside the window's trailing safe area.
            // UIKit can report a horizontal safe area larger than the bar itself; applying it
            // would collapse the item width to zero.
            let horizontalSafeInsets = insets.left + insets.right
            let insetLeft = horizontalSafeInsets < bounds.width ? insets.left : 0
            let insetRight = horizontalSafeInsets < bounds.width ? insets.right : 0
            var fallbackLeft = insetLeft + itemEdgeInsets.left
            var fallbackWidth = max(0, bounds.width - fallbackLeft - insetRight - itemEdgeInsets.right)
            if fallbackWidth <= 0 {
                fallbackLeft = itemEdgeInsets.left
                fallbackWidth = max(0, bounds.width - itemEdgeInsets.left - itemEdgeInsets.right)
            }
            left = fallbackLeft
            width = fallbackWidth
        }
        guard width > 0 else {
            return
        }
        
        let count = CGFloat(containers.count)
        let itemHeight = min(49.0, height / count)
        let totalHeight = itemHeight * count
        // The system anchors the tab bar toward the bottom of the vertical rail.
        var y = top + max(0, height - totalHeight)
        for container in containers {
            container.frame = CGRect(x: left, y: y, width: width, height: itemHeight)
            y += itemHeight
        }
    }
    
    private func verticalBarColumnRect() -> CGRect? {
        guard #available(iOS 27.1, *) else {
            return nil
        }
        guard let window = self.window else {
            return nil
        }
        let rectEdge: UIRectEdge
        switch traitCollection.verticalBarEdge {
        case .leading:
            rectEdge = .left
        case .trailing:
            rectEdge = .right
        case .unspecified:
            let barFrame = self.convert(self.bounds, to: window)
            rectEdge = barFrame.midX > window.bounds.midX ? .right : .left
        @unknown default:
            return nil
        }
        // 48pt is the measured width of the system's vertical tab column on iPhone Duo (iOS 27.1).
        let region = UIView.LayoutRegion.bar(onEdge: rectEdge, extent: 48.0)
        let edgeInsets = window.edgeInsets(for: region)
        let columnInWindow = window.bounds.inset(by: edgeInsets)
        guard columnInWindow.width > 0, columnInWindow.height > 0 else {
            return nil
        }
        let column = self.convert(columnInWindow, from: window)
        guard column.width > 0, column.height > 0 else {
            return nil
        }
        return column
    }
    
    private func systemTabBarButtons() -> [UIView] {
        var buttons = [UIView]()
        collectSystemTabBarButtons(in: self, into: &buttons)
        let buttonIdentifiers = Set(buttons.map { ObjectIdentifier($0) })
        return buttons.filter { button in
            var ancestor = button.superview
            while let view = ancestor {
                if buttonIdentifiers.contains(ObjectIdentifier(view)) {
                    return false
                }
                ancestor = view.superview
            }
            return true
        }
    }
    
    private func collectSystemTabBarButtons(in view: UIView, into buttons: inout [UIView]) {
        for subview in view.subviews {
            if NSStringFromClass(type(of: subview)).hasSuffix("UITabBarButton") {
                buttons.append(subview)
            }
            collectSystemTabBarButtons(in: subview, into: &buttons)
        }
    }
    
    private var layoutSafeAreaInsets: UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return safeAreaInsets
        }
        return .zero
    }
    
    private func usesFlatLayout() -> Bool {
        if #available(iOS 26.0, *) {
            return hasCustomItems
        }
        return false
    }
    
    private func canUseSystemLayout(tabBarButtons: [UIView]) -> Bool {
        guard tabBarButtons.count >= containers.count else {
            return false
        }
        for idx in containers.indices {
            let frame = self.convert(tabBarButtons[idx].bounds, from: tabBarButtons[idx])
            if frame.isEmpty {
                return false
            }
        }
        return true
    }
    
    private func layoutContainers(withCustomPositioning positioning: ESTabBarItemPositioning) {
        guard !containers.isEmpty else {
            return
        }
        var x: CGFloat = itemEdgeInsets.left
        var y: CGFloat = itemEdgeInsets.top
        if positioning == .fillExcludeSeparator, y <= 0.0 {
            y += 1.0
        }
        let width = max(0.0, bounds.size.width - itemEdgeInsets.left - itemEdgeInsets.right)
        let height = max(0.0, bounds.size.height - y - itemEdgeInsets.bottom)
        let eachWidth = itemWidth == 0.0 ? width / CGFloat(containers.count) : itemWidth
        let eachSpacing = itemSpacing == 0.0 ? 0.0 : itemSpacing
        
        for container in containers {
            container.frame = CGRect.init(x: x, y: y, width: eachWidth, height: height)
            x += eachWidth
            x += eachSpacing
        }
    }
    
    private func layoutContainersWithFlatStyle() {
        guard !containers.isEmpty else {
            return
        }
        
        let insets = layoutSafeAreaInsets
        let left = insets.left + itemEdgeInsets.left
        let right = insets.right + itemEdgeInsets.right
        let top = insets.top + itemEdgeInsets.top
        let bottom = insets.bottom + itemEdgeInsets.bottom
        let availableWidth = max(0, bounds.width - left - right)
        let rawHeight = max(0, bounds.height - top - bottom)
        var itemHeight = rawHeight
        if (traitCollection.horizontalSizeClass == .compact || traitCollection.userInterfaceIdiom == .phone), itemHeight > 49.0 {
            itemHeight = 49.0
        }
        guard availableWidth > 0, itemHeight > 0 else {
            return
        }
        let contentRect = CGRect(x: left, y: top, width: availableWidth, height: itemHeight)
        
        var centersItems = false
        if let positioning = itemCustomPositioning {
            centersItems = positioning == .centered || (positioning == .automatic && traitCollection.horizontalSizeClass == .regular)
        }
        
        let segments = horizontalLayoutSegments(in: contentRect)
        if segments.count > 1, containers.count >= segments.count {
            let counts = containerCounts(for: containers.count, segments: segments)
            var start = 0
            for (segment, count) in zip(segments, counts) {
                let end = min(start + count, containers.count)
                if start < end {
                    layoutContainers(containers[start..<end], in: segment, centersItems: centersItems)
                }
                start = end
            }
        } else {
            layoutContainers(containers[...], in: contentRect, centersItems: centersItems)
        }
    }
    
    private func layoutContainers(_ group: ArraySlice<ESTabBarItemContainer>, in rect: CGRect, centersItems: Bool) {
        guard !group.isEmpty, rect.width > 0, rect.height > 0 else {
            return
        }
        let count = CGFloat(group.count)
        let spacing = itemSpacing > 0.0 ? itemSpacing : 0.0
        var width = itemWidth
        if width <= 0.0 {
            width = centersItems ? 80.0 : rect.width / count
        }
        var totalWidth = width * count + spacing * CGFloat(max(0, group.count - 1))
        if totalWidth > rect.width {
            width = max(0, (rect.width - spacing * CGFloat(max(0, group.count - 1))) / count)
            totalWidth = width * count + spacing * CGFloat(max(0, group.count - 1))
        }
        var x = rect.minX
        if centersItems {
            x += max(0, (rect.width - totalWidth) / 2.0)
        }
        for container in group {
            container.frame = CGRect(x: x, y: rect.minY, width: width, height: rect.height)
            x += width + spacing
        }
    }
    
    private func horizontalLayoutSegments(in rect: CGRect) -> [CGRect] {
        var segments = [rect]
        if #available(iOS 27.1, *) {
            let regions = self.reservedRegions(kind: .division)
            for region in regions where region.isActive {
                let reserved = region.frame
                guard reserved.maxX > rect.minX, reserved.minX < rect.maxX else {
                    continue
                }
                var next = [CGRect]()
                for segment in segments {
                    if reserved.maxX <= segment.minX || reserved.minX >= segment.maxX {
                        next.append(segment)
                        continue
                    }
                    let leftWidth = max(0, reserved.minX - segment.minX)
                    if leftWidth > 0 {
                        next.append(CGRect(x: segment.minX, y: segment.minY, width: leftWidth, height: segment.height))
                    }
                    let rightStart = max(segment.minX, reserved.maxX)
                    let rightWidth = max(0, segment.maxX - rightStart)
                    if rightWidth > 0 {
                        next.append(CGRect(x: rightStart, y: segment.minY, width: rightWidth, height: segment.height))
                    }
                }
                segments = next
            }
        }
        let result = segments.filter { $0.width > 0 }.sorted { $0.minX < $1.minX }
        return result.isEmpty ? [rect] : result
    }
    
    private func containerCounts(for total: Int, segments: [CGRect]) -> [Int] {
        guard !segments.isEmpty else {
            return []
        }
        if total <= segments.count {
            return segments.enumerated().map { $0.offset < total ? 1 : 0 }
        }
        let totalWidth = segments.reduce(0) { $0 + $1.width }
        guard totalWidth > 0 else {
            return segments.map { _ in 0 }
        }
        var counts = segments.map { segment in
            max(1, Int((CGFloat(total) * segment.width / totalWidth).rounded()))
        }
        var sum = counts.reduce(0, +)
        while sum > total {
            if let index = counts.indices.filter({ counts[$0] > 1 }).max(by: { segments[$0].width < segments[$1].width }) {
                counts[index] -= 1
                sum -= 1
            } else {
                break
            }
        }
        while sum < total {
            if let index = segments.indices.max(by: { segments[$0].width / CGFloat(max(1, counts[$0])) < segments[$1].width / CGFloat(max(1, counts[$1])) }) {
                counts[index] += 1
                sum += 1
            } else {
                break
            }
        }
        return counts
    }
    
    #if DEBUG
    private var isDebugLayoutLoggingEnabled: Bool {
        return ProcessInfo.processInfo.environment["ESTAB_BAR_DEBUG_LAYOUT"] == "1"
    }
    
    private func debugDescription(of view: UIView, depth: Int) -> String {
        guard depth < 3 else {
            return ""
        }
        return view.subviews.map { subview in
            let nested = debugDescription(of: subview, depth: depth + 1)
            let description = "\(NSStringFromClass(type(of: subview))) frame=\(subview.frame) hidden=\(subview.isHidden)"
            return nested.isEmpty ? description : "\(description) [\(nested)]"
        }.joined(separator: " | ")
    }
    
    private func debugLogLayoutIfNeeded() {
        guard isDebugLayoutLoggingEnabled else {
            return
        }
        var lines = [String]()
        lines.append("ESTabBar vertical=\(isVerticalLayout) bounds=\(bounds) frame=\(frame) safe=\(layoutSafeAreaInsets) window=\(String(describing: window?.bounds))")
        if #available(iOS 27.1, *) {
            lines.append("verticalBarEdge=\(traitCollection.verticalBarEdge.rawValue)")
            let regions = self.reservedRegions(kind: .division)
            lines.append("division=\(regions.map { "\($0.frame) active=\($0.isActive)" })")
            lines.append("column=\(String(describing: verticalBarColumnRect()))")
        }
        lines.append("margins=\(layoutMargins) windowSafe=\(String(describing: window?.safeAreaInsets))")
        lines.append("super=\(String(describing: superview.map { "\(NSStringFromClass(type(of: $0))) frame=\($0.frame) bounds=\($0.bounds)" }))")
        lines.append("subviews=\(debugDescription(of: self, depth: 0))")
        lines.append("buttons=\(systemTabBarButtons().map { "\(NSStringFromClass(type(of: $0))) frame=\(convert($0.bounds, from: $0)) hidden=\($0.isHidden)" })")
        lines.append("containers=\(containers.map { "\($0.frame)" })")
        lines.append("items=\(items?.map { $0.title ?? "" } ?? [])")
        let description = lines.joined(separator: "\n")
        if description != lastDebugLayoutDescription {
            lastDebugLayoutDescription = description
            NSLog("%@", description)
        }
    }
    #endif
}

internal extension ESTabBar /* Actions */ {
    
    func isMoreItem(_ index: Int) -> Bool {
        return ESTabBarController.isShowingMore(tabBarController) && (index == (items?.count ?? 0) - 1)
    }
    
    func removeAll() {
        for container in containers {
            container.removeFromSuperview()
        }
        containers.removeAll()
    }
    
    func reload() {
        removeAll()
        guard let tabBarItems = self.items else {
            ESTabBarController.printError("empty items")
            return
        }
        for (idx, item) in tabBarItems.enumerated() {
            let container = ESTabBarItemContainer.init(self, tag: 1000 + idx)
            self.addSubview(container)
            self.containers.append(container)
            
            if let item = item as? ESTabBarItem {
                item.contentView.isVerticalLayout = self.isVerticalLayout
                container.addSubview(item.contentView)
            }
            if self.isMoreItem(idx), let moreContentView = moreContentView {
                moreContentView.isVerticalLayout = self.isVerticalLayout
                container.addSubview(moreContentView)
            }
        }
        
        self.updateAccessibilityLabels()
        self.applyLiquidGlassCompatibilityIfNeeded()
        self.setNeedsLayout()
    }
    
    @objc func highlightAction(_ sender: AnyObject?) {
        guard let container = sender as? ESTabBarItemContainer else {
            return
        }
        let newIndex = max(0, container.tag - 1000)
        guard newIndex < items?.count ?? 0, let item = self.items?[newIndex], item.isEnabled == true else {
            return
        }
        
        if (customDelegate?.tabBar(self, shouldSelect: item) ?? true) == false {
            return
        }
        
        if let item = item as? ESTabBarItem {
            item.contentView.highlight(animated: true, completion: nil)
        } else if self.isMoreItem(newIndex) {
            moreContentView?.highlight(animated: true, completion: nil)
        }
    }
    
    @objc func dehighlightAction(_ sender: AnyObject?) {
        guard let container = sender as? ESTabBarItemContainer else {
            return
        }
        let newIndex = max(0, container.tag - 1000)
        guard newIndex < items?.count ?? 0, let item = self.items?[newIndex], item.isEnabled == true else {
            return
        }
        
        if (customDelegate?.tabBar(self, shouldSelect: item) ?? true) == false {
            return
        }
        
        if let item = item as? ESTabBarItem {
            item.contentView.dehighlight(animated: true, completion: nil)
        } else if self.isMoreItem(newIndex) {
            moreContentView?.dehighlight(animated: true, completion: nil)
        }
    }
    
    @objc func selectAction(_ sender: AnyObject?) {
        guard let container = sender as? ESTabBarItemContainer else {
            return
        }
        select(itemAtIndex: container.tag - 1000, animated: true)
    }
    
    @objc func select(itemAtIndex idx: Int, animated: Bool) {
        let newIndex = max(0, idx)
        let currentIndex = (selectedItem != nil) ? (items?.firstIndex(of: selectedItem!) ?? -1) : -1
        guard newIndex < items?.count ?? 0, let item = self.items?[newIndex], item.isEnabled == true else {
            return
        }
        
        if (customDelegate?.tabBar(self, shouldSelect: item) ?? true) == false {
            return
        }
        
        if (customDelegate?.tabBar(self, shouldHijack: item) ?? false) == true {
            customDelegate?.tabBar(self, didHijack: item)
            if animated {
                if let item = item as? ESTabBarItem {
                    item.contentView.select(animated: animated, completion: {
                        item.contentView.deselect(animated: false, completion: nil)
                    })
                } else if self.isMoreItem(newIndex) {
                    moreContentView?.select(animated: animated, completion: {
                        self.moreContentView?.deselect(animated: animated, completion: nil)
                    })
                }
            }
            return
        }
        
        if currentIndex != newIndex {
            if currentIndex != -1 && currentIndex < items?.count ?? 0{
                if let currentItem = items?[currentIndex] as? ESTabBarItem {
                    currentItem.contentView.deselect(animated: animated, completion: nil)
                } else if self.isMoreItem(currentIndex) {
                    moreContentView?.deselect(animated: animated, completion: nil)
                }
            }
            if let item = item as? ESTabBarItem {
                item.contentView.select(animated: animated, completion: nil)
            } else if self.isMoreItem(newIndex) {
                moreContentView?.select(animated: animated, completion: nil)
            }
        } else if currentIndex == newIndex {
            if let item = item as? ESTabBarItem {
                item.contentView.reselect(animated: animated, completion: nil)
            } else if self.isMoreItem(newIndex) {
                moreContentView?.reselect(animated: animated, completion: nil)
            }
            
            if let tabBarController = tabBarController {
                var navVC: UINavigationController?
                if let n = tabBarController.selectedViewController as? UINavigationController {
                    navVC = n
                } else if let n = tabBarController.selectedViewController?.navigationController {
                    navVC = n
                }
                
                if let navVC = navVC {
                    if navVC.viewControllers.contains(tabBarController) {
                        if navVC.viewControllers.count > 1 && navVC.viewControllers.last != tabBarController {
                            navVC.popToViewController(tabBarController, animated: true);
                        }
                    } else {
                        if navVC.viewControllers.count > 1 {
                            navVC.popToRootViewController(animated: animated)
                        }
                    }
                }
            
            }
        }
        
        delegate?.tabBar?(self, didSelect: item)
        self.updateAccessibilityLabels()
    }
    
    func updateAccessibilityLabels() {
        guard let tabBarItems = self.items, tabBarItems.count == self.containers.count else {
            return
        }
        
        for (idx, item) in tabBarItems.enumerated() {
            let container = self.containers[idx]
            container.accessibilityIdentifier = item.accessibilityIdentifier
            container.accessibilityTraits = item.accessibilityTraits
            
            if item == selectedItem {
                container.accessibilityTraits = container.accessibilityTraits.union(.selected)
            }
            
            if let explicitLabel = item.accessibilityLabel {
                container.accessibilityLabel = explicitLabel
                container.accessibilityHint = item.accessibilityHint ?? container.accessibilityHint
            } else {
                var accessibilityTitle = ""
                if let item = item as? ESTabBarItem {
                    accessibilityTitle = item.accessibilityLabel ?? item.title ?? ""
                }
                if self.isMoreItem(idx) {
                    accessibilityTitle = NSLocalizedString("More_TabBarItem", bundle: Bundle(for:ESTabBarController.self), comment: "")
                }
                
                let formatString = NSLocalizedString(item == selectedItem ? "TabBarItem_Selected_AccessibilityLabel" : "TabBarItem_AccessibilityLabel",
                                                     bundle: Bundle(for: ESTabBarController.self),
                                                     comment: "")
                container.accessibilityLabel = String(format: formatString, accessibilityTitle, idx + 1, tabBarItems.count)
            }
            
        }
    }
}

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
        
        let tabBarButtons = systemTabBarButtons()
        let usesFlatLayout = self.usesFlatLayout()
        
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
        
        if usesFlatLayout {
            for tabBarButton in tabBarButtons {
                tabBarButton.isHidden = true
            }
        } else {
            for (idx, item) in tabBarItems.enumerated() {
                guard idx < tabBarButtons.count else {
                    continue
                }
                let isCustomItem = item is ESTabBarItem || (isMoreItem(idx) && moreContentView != nil)
                tabBarButtons[idx].isHidden = isCustomItem
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
        
        if !usesFlatLayout, self.canUseSystemLayout(tabBarButtons: tabBarButtons) {
            for (idx, container) in containers.enumerated() {
                container.frame = tabBarButtons[idx].frame
            }
            return
        }
        
        self.layoutContainersWithFlatStyle()
    }
    
    private func systemTabBarButtons() -> [UIView] {
        return subviews.filter { subview in
            return NSStringFromClass(type(of: subview)).hasSuffix("UITabBarButton")
            }.sorted { (subview1, subview2) -> Bool in
                return subview1.frame.origin.x < subview2.frame.origin.x
        }
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
            if tabBarButtons[idx].frame.isEmpty {
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
        
        var bottomInset: CGFloat = 0.0
        if #available(iOS 11.0, *) {
            bottomInset = safeAreaInsets.bottom
        }
        let rawHeight = max(0.0, bounds.size.height - bottomInset - itemEdgeInsets.top - itemEdgeInsets.bottom)
        var itemHeight = rawHeight
        if traitCollection.horizontalSizeClass == .compact, itemHeight > 49.0 {
            itemHeight = 49.0
        }
        let y = itemEdgeInsets.top
        
        var centersItems = false
        if let positioning = itemCustomPositioning {
            centersItems = positioning == .centered || (positioning == .automatic && traitCollection.horizontalSizeClass == .regular)
        }
        
        if centersItems {
            var width = itemWidth
            if width <= 0.0 {
                width = 80.0
            }
            let spacing = itemSpacing > 0.0 ? itemSpacing : 0.0
            let totalWidth = width * CGFloat(containers.count) + spacing * CGFloat(max(0, containers.count - 1))
            var x = max(itemEdgeInsets.left, (bounds.size.width - totalWidth) / 2.0)
            for container in containers {
                container.frame = CGRect.init(x: x, y: y, width: width, height: itemHeight)
                x += width + spacing
            }
        } else {
            let availableWidth = max(0.0, bounds.size.width - itemEdgeInsets.left - itemEdgeInsets.right)
            let width = itemWidth > 0.0 ? itemWidth : availableWidth / CGFloat(containers.count)
            let spacing = itemSpacing > 0.0 ? itemSpacing : 0.0
            var x = itemEdgeInsets.left
            for container in containers {
                container.frame = CGRect.init(x: x, y: y, width: width, height: itemHeight)
                x += width + spacing
            }
        }
    }
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
                container.addSubview(item.contentView)
            }
            if self.isMoreItem(idx), let moreContentView = moreContentView {
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

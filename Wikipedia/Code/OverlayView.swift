//
//  OverlayView.swift
//  Wikipedia
//
//  Created by Chris Eidhof on 25.06.18.
//  Copyright © 2018 Wikimedia Foundation. All rights reserved.
//

import UIKit

protocol OverlayViewDelegate: AnyObject {
    var overlayContentHeight: CGFloat { get }
}

final class OverlayView: RoundedCornerView {
    @IBOutlet weak var listAndSearchOverlaySliderSeparator: UIView!
    @IBOutlet weak var listAndSearchOverlayBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlayHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlaySliderHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlaySliderView: UIView!
    
    weak var delegate: OverlayViewDelegate!

    let overlayMidHeight: CGFloat = 388
    var overlayMinHeight: CGFloat {
        get {
            return delegate.overlayContentHeight + listAndSearchOverlaySliderHeightConstraint.constant
        }
    }
    var overlayMaxHeight: CGFloat {
        get {
            return self.superview!.bounds.size.height - frame.minY - listAndSearchOverlayBottomConstraint.constant
        }
    }

    fileprivate var overlaySliderPanGestureRecognizer: UIPanGestureRecognizer?

    func enablePanning() {
        let panGR = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        listAndSearchOverlaySliderView.addGestureRecognizer(panGR)
        overlaySliderPanGestureRecognizer = panGR
    }
    
    func disablePanning() {
        guard let panGR = overlaySliderPanGestureRecognizer else { return }
        listAndSearchOverlaySliderView.removeGestureRecognizer(panGR)
    }
    
    func apply(theme: Theme) {
        backgroundColor = theme.colors.chromeBackground
        listAndSearchOverlaySliderView.backgroundColor = theme.colors.chromeBackground
        listAndSearchOverlaySliderView.tintColor = theme.colors.secondaryText
        
        listAndSearchOverlaySliderSeparator.backgroundColor = theme.colors.midBackground
        
    }
    
    enum OverlayState {
        case min
        case mid
        case max
    }
    
    func set(overlayState: OverlayState, withVelocity velocity: CGFloat, animated: Bool) {
        let currentHeight = listAndSearchOverlayHeightConstraint.constant
        let newHeight: CGFloat
        switch overlayState {
        case .min:
            newHeight = overlayMinHeight
        case .max:
            newHeight = overlayMaxHeight
        default:
            newHeight = overlayMidHeight
        }
        let springVelocity = velocity / (newHeight - currentHeight)
        superview!.layoutIfNeeded() // todo
        let animations = {
            self.listAndSearchOverlayHeightConstraint.constant = newHeight
            self.superview!.layoutIfNeeded()
        }
        let duration: TimeInterval = 0.5
        self.overlayState = overlayState
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: springVelocity, options: [.allowUserInteraction], animations: animations, completion: { (didFinish) in
            if overlayState == .max {
                self.listAndSearchOverlayHeightConstraint.isActive = false
                self.listAndSearchOverlayBottomConstraint.isActive = true
            } else {
                self.listAndSearchOverlayHeightConstraint.isActive = true
                self.listAndSearchOverlayBottomConstraint.isActive = false
            }
        })
    }
    
    var overlayState = OverlayState.mid
    var initialOverlayHeightForPan: CGFloat?

    
    @objc func handlePanGesture(_ panGR: UIPanGestureRecognizer) {
        let minHeight = overlayMinHeight
        let maxHeight = overlayMaxHeight
        let midHeight = overlayMidHeight
        switch panGR.state {
        case .possible:
            fallthrough
        case .began:
            fallthrough
        case .changed:
            let initialHeight: CGFloat
            if let height = initialOverlayHeightForPan {
                initialHeight = height
            } else {
                if (overlayState == .max) {
                    listAndSearchOverlayHeightConstraint.constant = frame.height
                }
                initialHeight = listAndSearchOverlayHeightConstraint.constant
                initialOverlayHeightForPan = initialHeight
                listAndSearchOverlayHeightConstraint.isActive = true
                listAndSearchOverlayBottomConstraint.isActive = false
            }
            listAndSearchOverlayHeightConstraint.constant = max(minHeight, initialHeight + panGR.translation(in: self).y)
        case .ended:
            fallthrough
        case .failed:
            fallthrough
        case .cancelled:
            let currentHeight = listAndSearchOverlayHeightConstraint.constant
            let newState: OverlayState
            if currentHeight <= midHeight {
                let min: Bool = currentHeight - minHeight <= midHeight - currentHeight
                if min {
                    newState = .min
                } else {
                    newState = .mid
                }
            } else {
                let mid: Bool = currentHeight - midHeight <= maxHeight - currentHeight
                if mid {
                    newState = .mid
                } else {
                    newState = .max
                }
            }
            set(overlayState: newState, withVelocity: panGR.velocity(in: self).y, animated: true)
            initialOverlayHeightForPan = nil
            break
        }
    }
}

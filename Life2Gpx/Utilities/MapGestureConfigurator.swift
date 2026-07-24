import SwiftUI
import MapKit

/// A utility view that finds the underlying MKMapView and injects custom gesture logic.
/// This allows us to use 1-finger for drawing/moving points while keeping the native 2-finger panning.
struct MapGestureConfigurator: UIViewRepresentable {
    var isEnabled: Bool
    var onDraw: (CGPoint, UIGestureRecognizer.State) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        
        DispatchQueue.main.async {
            if let mapView = findMKMapView(from: view) {
                // Add our custom 1-finger pan gesture
                let drawPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
                drawPan.maximumNumberOfTouches = 1
                drawPan.delegate = context.coordinator
                mapView.addGestureRecognizer(drawPan)
                context.coordinator.drawPan = drawPan
                
                // Add our custom 1-finger tap gesture
                let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
                tap.numberOfTouchesRequired = 1
                tap.delegate = context.coordinator
                mapView.addGestureRecognizer(tap)
                context.coordinator.tap = tap
                
                context.coordinator.mapView = mapView
                updateGestures(mapView: mapView, coordinator: context.coordinator, isEnabled: isEnabled)
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // We also need to update the parent reference in the coordinator
        context.coordinator.parent = self
        
        if let mapView = context.coordinator.mapView {
            updateGestures(mapView: mapView, coordinator: context.coordinator, isEnabled: isEnabled)
        } else {
            DispatchQueue.main.async {
                if let mapView = findMKMapView(from: uiView) {
                    context.coordinator.mapView = mapView
                    updateGestures(mapView: mapView, coordinator: context.coordinator, isEnabled: isEnabled)
                }
            }
        }
    }
    
    private func updateGestures(mapView: MKMapView, coordinator: Coordinator, isEnabled: Bool) {
        // Adjust map's native pan gesture
        for gesture in mapView.gestureRecognizers ?? [] {
            if let pan = gesture as? UIPanGestureRecognizer, pan !== coordinator.drawPan {
                pan.minimumNumberOfTouches = isEnabled ? 2 : 1
            }
        }
        
        coordinator.drawPan?.isEnabled = isEnabled
        coordinator.tap?.isEnabled = isEnabled
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapGestureConfigurator
        weak var mapView: MKMapView?
        weak var drawPan: UIPanGestureRecognizer?
        weak var tap: UITapGestureRecognizer?
        
        init(_ parent: MapGestureConfigurator) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            parent.onDraw(gesture.location(in: view), gesture.state)
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            parent.onDraw(gesture.location(in: view), .began)
            parent.onDraw(gesture.location(in: view), .ended)
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false // We want exclusive control for our 1-finger gestures
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Force the map's gestures to wait for ours.
            // If our gesture succeeds (1 finger), the map's gesture fails.
            // If our gesture fails (2 fingers), the map's gesture proceeds!
            if gestureRecognizer == drawPan || gestureRecognizer == tap {
                return true
            }
            return false
        }
    }
    
    private func findMKMapView(from view: UIView) -> MKMapView? {
        var current: UIView? = view
        while let currentView = current {
            if let map = searchForMap(in: currentView) {
                return map
            }
            current = currentView.superview
        }
        return nil
    }
    
    private func searchForMap(in view: UIView) -> MKMapView? {
        if let map = view as? MKMapView { return map }
        for subview in view.subviews {
            if let map = searchForMap(in: subview) { return map }
        }
        return nil
    }
}

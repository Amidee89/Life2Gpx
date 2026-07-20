//
//  MapControlsView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 25.4.2024.
//
import SwiftUI
import MapKit
import CoreGPX
import Foundation


let calendar = Calendar.current

struct MapControlsView: View {
    var onCenter: () -> Void
    var onSelectToday: () -> Void
    @Binding var selectedDate: Date
    @Binding var timelineObjects: [TimelineObject]
    var safeAreaTop: CGFloat
    var body: some View {
        GeometryReader { geometry in
            let noDataHeight: CGFloat = timelineObjects.isEmpty ? 92 : 0
            let dynamicTopPadding = max(0, min(safeAreaTop, geometry.size.height - (136 + noDataHeight)))
            
            VStack {
                Group{
                    if timelineObjects.isEmpty{
                        Text("No data for this day")
                            .padding()
                            .background(Color.black.opacity(0.8))
                            .foregroundColor(Color.white)
                            .cornerRadius(8)
                            .padding()
                    }
                }
                Spacer()
                HStack {
                    Button(action: onCenter) {
                        Image(systemName: "location.viewfinder")
                            .frame(width: 20, height: 20)
                            .font(.system(size: 22))
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
                    Spacer()
                    if !calendar.isDate(selectedDate, inSameDayAs: Date()) {
                        Button(action: onSelectToday) {
                            Image(systemName: "forward")
                                .frame(width: 20, height: 20)
                                .font(.system(size: 22))
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                                .shadow(radius: 3)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

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
    var onRefresh: () -> Void
    var onCenter: () -> Void
    var onSelectToday: () -> Void
    @Binding var selectedDate: Date
    @Binding var timelineObjects: [TimelineObject]
    var body: some View {
        VStack {
            HStack{
                Spacer()
                if !calendar.isDate(selectedDate, inSameDayAs: Date()){
                    Button(action: onSelectToday){
                        Image(systemName: "forward")
                            .font(.title)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                            .scaleEffect(0.8)
                    }
                    .padding(.trailing, 30)
                    .padding(.top,30)
                    .transition(.scale)
                }
            }
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
                        .font(.title)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                        .scaleEffect(0.8)
                }
                .padding(.leading, 30)
                .padding(.bottom, 30)
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                        .scaleEffect(0.8)
                }
                .padding(.trailing, 30)
                .padding(.bottom, 30)
            }
        }
    }
}

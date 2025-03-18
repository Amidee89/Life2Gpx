private func importArcPlaces(timer: PerformanceTimer) async throws {

    while let fileUrl = enumerator.nextObject() as? URL {

        for place in places {
            let startProcessPlace = Date()
            
            let duplicate = try await checkForDuplicates(place)
            
            if let duplicate = duplicate {
                duplicateCount += 1
                
                if importOptions.ignoreDuplicates {
                    print("Skipping duplicate: \(place.name) (ID: \(place.placeId))")
                    continue
                } else {
                    if needsUpdate {
                        try await PlaceManager.shared.editPlace(original: duplicate, edited: updatedPlace, batch: true)
                        mergedCount += 1
                    }
                }
            } else {
                try await PlaceManager.shared.addPlace(place, batch: true)
                addedCount += 1
            }
        }

        try FileManagerUtil.shared.moveFileToImportDone(fileUrl, sessionTimestamp: timestamp)
        
        if processedFiles % 20 == 0 || processedFiles == totalFiles {  
            await MainActor.run {
                processedFiles += 1
                progress = "Processing file \(processedFiles) of \(totalFiles)"
                progressValue = 0.1 + (Double(processedFiles) / Double(totalFiles)) * 0.8
            }
        } else {
            processedFiles += 1
        }
    }
    
    // Final UI update
    await MainActor.run {
        progressValue = 0.9
        progress = "Completed: Imported \(addedCount) places, found \(duplicateCount) duplicates"
    }

    // ... existing code ...
} 
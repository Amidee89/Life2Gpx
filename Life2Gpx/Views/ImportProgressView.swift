private func importArcPlaces(timer: PerformanceTimer) async throws {
    // ... existing code ...

    while let fileUrl = enumerator.nextObject() as? URL {
        // ... existing code ...

        for place in places {
            let startProcessPlace = Date()
            
            let duplicate = try await checkForDuplicates(place)
            
            if let duplicate = duplicate {
                // Update counts locally instead of triggering UI updates
                duplicateCount += 1
                
                if importOptions.ignoreDuplicates {
                    print("Skipping duplicate: \(place.name) (ID: \(place.placeId))")
                    continue
                } else {
                    // ... handle duplicate logic ...
                    if needsUpdate {
                        try await PlaceManager.shared.editPlace(original: duplicate, edited: updatedPlace, batch: true)
                        mergedCount += 1
                    }
                }
            } else {
                try await PlaceManager.shared.addPlace(place, batch: true)
                // Update count locally
                addedCount += 1
            }
        }

        // Move file processing and batch UI updates outside the place loop
        try FileManagerUtil.shared.moveFileToImportDone(fileUrl, sessionTimestamp: timestamp)
        
        // Update UI only once per file instead of per place
        if processedFiles % 10 == 0 || processedFiles == totalFiles {  // Update every 10 files or on last file
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
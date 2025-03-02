import Foundation

class FileManagerUtil {
    static let shared = FileManagerUtil()
    
    private init() {
        setupFolderStructure()
    }
    
    private func setupFolderStructure() {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Define required folders
        let folders = [
            "Import",
            "Import/Arc",
            "Places",
            "Backups"
        ]
        
        // Create each folder if it doesn't exist
        for folder in folders {
            let folderUrl = documentsUrl.appendingPathComponent(folder)
            if !fileManager.fileExists(atPath: folderUrl.path) {
                do {
                    try fileManager.createDirectory(at: folderUrl, 
                                                  withIntermediateDirectories: true)
                    print("Created directory: \(folder)")
                } catch {
                    print("Error creating directory \(folder): \(error)")
                }
            }
        }
    }
    
    func moveFileToImportDone(_ fileUrl: URL) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let doneFolder = documentsUrl.appendingPathComponent("Import/Done")
        
        let destinationUrl = doneFolder.appendingPathComponent(fileUrl.lastPathComponent)
        
        if fileManager.fileExists(atPath: destinationUrl.path) {
            try fileManager.removeItem(at: destinationUrl)
        }
        
        try fileManager.moveItem(at: fileUrl, to: destinationUrl)
    }
} 

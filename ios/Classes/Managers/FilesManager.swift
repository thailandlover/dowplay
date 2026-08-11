//
//  FilesManager.swift
//  KeeCustomPlayer
//
//  Created by Ahmed Qazzaz on 20/12/2022.
//

import Foundation


public class FilesManager {
    private var fm = FileManager.default
    static var shared = FilesManager()
    private var userSignature : String = ""
            
    private var documentsDirectory : URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    var cache : URL{
        return documentsDirectory.appendingPathComponent("DownloadCache")
    }
    
    @discardableResult
    func setUser(_ userSignature : String)->FilesManager{
        self.userSignature = userSignature
        return self
    }
    
    func forUser(_ userSignature : String)->FilesManager{
        self.userSignature = userSignature
        for type in [MediaManager.MediaType.movie, MediaManager.MediaType.series]{
            let userCacheFolder = cache
                .appendingPathComponent(type.version_3_value)
                .appendingPathComponent(userSignature)
            if !checkFolderExistance(dir: userCacheFolder.path) {
                try? fm.createDirectory(at: userCacheFolder,
                                           withIntermediateDirectories: true)
            }
        }
                      
        return self
    }
    
    private init() {
        do{
            try createCachingDirectory()
        }catch{
            
        }
    }
    
    
    
    
    private func createCachingDirectory()throws{
        let dir = documentsDirectory.appendingPathComponent("DownloadCache").path
        if !checkFolderExistance(dir: dir){
            try fm.createDirectory(at: documentsDirectory.appendingPathComponent("DownloadCache"),
                                       withIntermediateDirectories: true)
        }
        //Movies Folder
        let mDir = documentsDirectory.appendingPathComponent("DownloadCache")
            .appendingPathComponent(MediaManager.MediaType.movie.version_3_value, isDirectory: true)
            .path
        
        if !checkFolderExistance(dir: mDir){
            try fm.createDirectory(at: documentsDirectory.appendingPathComponent("DownloadCache")
                .appendingPathComponent(MediaManager.MediaType.movie.version_3_value, isDirectory: true),
                                       withIntermediateDirectories: true)
        }
        
        //Serise Folder
        let sDir = documentsDirectory.appendingPathComponent("DownloadCache")
            .appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true)
            .path
        
        if !checkFolderExistance(dir: sDir){
            try fm.createDirectory(at: documentsDirectory.appendingPathComponent("DownloadCache")
                .appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true),
                                       withIntermediateDirectories: true)
        }
    }
    
    
    
    
  
    /// Should be called after the download is finished
    /// This function is called by the DownloadedMedia Object
    func registerDownloadedMedia(_ downloadedMedia: DownloadedMedia) throws{
        if downloadedMedia.mediaType == .movie {
            self.saveMovieInfo(downloadedMedia)
        }else{
            if let group = downloadedMedia.group {
                var serise = Info(name: group.showName,
                                        id: group.showId)
                serise.info = group.info
                self.addSeries(serise)
                self.checkFolders(forSerise: serise, andSeasonID: group.seasonId)
                var season = Info(name: group.seasonName, id: group.seasonId)
                season.info = group.info
                self.saveSeasonInfo(season, forSerise: serise.id)
                self.moveEpisodeFile(downloadedMedia)
            }
        }
    }
    
    public func getDownloadeMovieById(_ id : String)throws -> DownloadedMedia? {
        return try Array(self.getDMList().values).first(where: {$0.mediaId == id})
    }
    
    public func deleteMovieBy(id : String)throws{
        var dmListContent = try self.getDMList()
        if var deletedItem = dmListContent.removeValue(forKey: id){
            deletedItem.signature = self.userSignature
            try? fm.removeItem(at: deletedItem.tempPath!)
            try? fm.removeItem(at: deletedItem.path)
            saveDMListContent(dmListContent)
        }
        
    }
    
    public func deleteEpisodeById(_ id: String, season: String, series: String){
        if let ep = getDownloadedEpisode(id: id, season: season, series: series) {
            deleteEpisode(ep)
            let numberOfEpisodesLeft = getEpisodes(seasonID: season, atSeriseId: series).count
            if numberOfEpisodesLeft == 0 {
                deleteSeason(season, tvShowId: series)
            }
        }
    }
    
    func deleteEpisode(_ e: DownloadedMedia) {
        // remove the episode file, and info file
        var ee = e
        ee.setUser(signature: userSignature)
        try? fm.removeItem(at: ee.tempPath!)
        try? fm.removeItem(at: ee.path)
        if let info = ee.episodeInfoPathURL{
            try? fm.removeItem(at: info)
        }
    }
    
    public func deleteSeason(_ seasonId : String, tvShowId: String){
        
        if var list = try?  getSeasonsListFile(forSerise: tvShowId) {
            list.removeAll(where: {$0.id == seasonId})
            saveSeasonsListFile(list, atSerise: tvShowId)
            
            
            let folder = cache
                .appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true)
                .appendingPathComponent(userSignature, isDirectory: true)
                .appendingPathComponent(tvShowId, isDirectory: true)
                .appendingPathComponent(seasonId, isDirectory: true)
            
            try? fm.removeItem(at: folder)
        }
        
        let numberOfSeasonsLeft = getSeasons(forSeriseID: tvShowId).count
        if numberOfSeasonsLeft == 0 {
            deleteTvShow(tvShowId)
        }
    }
    
    public func deleteTvShow(_ id: String){
        
        if var list = try? getSeriseListFile() {
            list.removeAll(where: {$0.id == id})
            saveSeriseListFile(list)
            
            let folder = cache
                .appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true)
                .appendingPathComponent(userSignature, isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
            
            try? fm.removeItem(at: folder)
        }
    }
    
    
    
    
    
    public func getDownloadedEpisode(id: String, season: String, series: String)->DownloadedMedia?{
        return getEpisodes(seasonID: season, atSeriseId: series).first(where: {$0.group?.episodeId == id})
    }
                
    public func getFileForMovie(mediaID: String)throws->URL?{
        return try DownloadedMedia.getMovieByID(id: mediaID, signature: userSignature)?.path
    }
    
    public func getFileForEpisode(id: String, season: String, series: String)throws->URL?{
        return  DownloadedMedia.getEpisodeByID(id: id, season: season, series: series, signature: userSignature)?.path
    }
    
    public func getAllDownloadedMedia()->[DownloadedMedia]{
        do{
            let movies : [DownloadedMedia] = try Array(self.getDMList().values)
            var result : [DownloadedMedia] = []
            result.append(contentsOf: movies)
            
            let allSerise = (try? self.getSeriseListFile()) ?? []
            for s in allSerise {
                var group = MediaGroup(showId: s.id, seasonId: "", episodeId: "", seasonName: s.name, showName: "")
                group.setData(newData: s.data)
                let dm = DownloadedMedia(mediaId: s.id, name: s.name, group: group, type: .SeriseInfo)
                result.append(dm)
            }

            return result
                        
        }catch{
            
        }
        return []
    }
    
    @discardableResult
    private func moveDownloadedFile(atPath path: URL, toCacheUsingName n: String, Extension ext: String ) throws -> URL{
        let destinationURL = cache.appendingPathComponent("\(n).\(ext)")
        try fm.moveItem(at: path, to: destinationURL)
        return destinationURL
    }
    
    private func checkFileExistance(filePath: String)->Bool{
        var isDir : ObjCBool = false
        if fm.fileExists(atPath: filePath, isDirectory: &isDir) {
            if !isDir.boolValue{
                return true
            }
        }
        return false
    }
    
    private func checkFolderExistance(dir: String)->Bool{
        var isDir : ObjCBool = false
        if fm.fileExists(atPath: dir, isDirectory: &isDir) {
            if isDir.boolValue{
                return true
            }
        }
        return false
    }
    
    func saveTempData(id: String, data: DownloadedMedia, user: String){
        let dirPath = cache.appendingPathComponent(user)
        let fullPath = dirPath.appendingPathComponent(id + ".keetmp")
        if checkFolderExistance(dir: dirPath.path) == false {
            try? fm.createDirectory(at: dirPath, withIntermediateDirectories: true)
        }
        if let data = try? JSONEncoder().encode(data) {
            try? data.write(to: fullPath)
        }
    }

    func clearTempDataFor(id: String, user: String){
        let dirPath = cache.appendingPathComponent(user)
        let fullPath = dirPath.appendingPathComponent(id + ".keetmp")
        try? fm.removeItem(at: fullPath)
    }

    func hasTempData(id: String, user: String)->Bool{
        let fullPath = cache.appendingPathComponent(user).appendingPathComponent(id + ".keetmp")
        return checkFileExistance(filePath: fullPath.path)
    }

    func getTempData(id: String, user: String)->DownloadedMedia?{
        let fullPath = cache.appendingPathComponent(user).appendingPathComponent(id + ".keetmp")
        guard let data = try? Data(contentsOf: fullPath) else {return nil}
        return try? JSONDecoder().decode(DownloadedMedia.self, from: data)
    }

    public func getTempData(user: String)->[DownloadedMedia]{
        var list : [DownloadedMedia] = []
        let dirPath = cache.appendingPathComponent(user)
        let contentsList = try? fm.contentsOfDirectory(at: dirPath, includingPropertiesForKeys: nil)
        for file in contentsList ?? [] {
            guard file.pathExtension == "keetmp" else {continue}
            if let data = try? Data(contentsOf: file){
                if var media = try? JSONDecoder().decode(DownloadedMedia.self, from: data) {
                    media.status = media.retrivalStatus == 0 ? .running : .suspended
                    media.setUser(signature: user)
                    list.append(media)
                }
            }
        }
        return list
    }

    //MARK: - Resume data
    /// Bytes iOS hands back when a transfer fails, so the download can continue instead of
    /// starting over.
    func saveResumeData(_ data: Data, id: String, user: String){
        let dirPath = cache.appendingPathComponent(user)
        if checkFolderExistance(dir: dirPath.path) == false {
            try? fm.createDirectory(at: dirPath, withIntermediateDirectories: true)
        }
        try? data.write(to: dirPath.appendingPathComponent(id + ".keeresume"))
    }

    func getResumeData(id: String, user: String)->Data?{
        let fullPath = cache.appendingPathComponent(user).appendingPathComponent(id + ".keeresume")
        return try? Data(contentsOf: fullPath)
    }

    func clearResumeData(id: String, user: String){
        let fullPath = cache.appendingPathComponent(user).appendingPathComponent(id + ".keeresume")
        try? fm.removeItem(at: fullPath)
    }
    
    
}

//MARK: - Movie Save/Load Functions
extension FilesManager {
    private func saveMovieInfo(_ media : DownloadedMedia){
        do{
            var downloadPath = media.mediaType.version_3_value + "/" + userSignature + "/" + media.mediaId
            try self.moveDownloadedFile(atPath: media.tempPath!,
                                        toCacheUsingName: downloadPath,
                                        Extension: "mp4")
            
            var dmListContent = try getDMList()
            dmListContent[media.mediaId] = media
            saveDMListContent(dmListContent)
            
            try self.moveDownloadedFile(atPath: media.tempPath!,
                                        toCacheUsingName: downloadPath,
                                        Extension: "mp4")
        }catch{
            print(error)
        }
    }
}

//MARK: - Serise Save/Load Functions
extension FilesManager {
    // GET Serise Info
    func getSeriseInfo(usingID id: String)->Info? {
        do{
            let list = try getSeriseListFile().filter({$0.id == id})
            if list.count > 0 {
                return list.first
            }
        }catch{
            print(error)
        }
        return nil
    }
    
    // GET Seasons for Serise
    public func getSeasons(forSeriseID id: String)->[DownloadedMedia] {
        do{
            if let info = getSeriseInfo(usingID: id){
                
                let list = try getSeasonsListFile(forSerise: id)
                return list.map({ season in
                    var group = MediaGroup(showId: info.id,
                                           seasonId: season.id,
                                           episodeId: "",
                                           seasonName: season.name,
                                           showName: info.name)
                    group.setData(newData: info.data)
                    return DownloadedMedia(mediaId: season.id, name: season.name, group: group, type: MediaRetrivalType.SeasonInfo)})
            }
            
            return []
        }catch{
            return []
        }
    }
        
    // GET Episodes for Season
    public func getEpisodes(seasonID id: String, atSeriseId: String)->[DownloadedMedia] {
        do{
            let path = "\(MediaManager.MediaType.series.version_3_value)/\(userSignature)/\(atSeriseId)/\(id)/"
            let fullPath = cache.appendingPathComponent(path)
            let items = try fm.contentsOfDirectory(atPath: fullPath.path)
            let filtteredItmes = items.filter({$0.contains(".keeinfo")})
            var result : [DownloadedMedia] = []
            for file in filtteredItmes {
                let filePath = fullPath.appendingPathComponent("\(file)")
                if let data = try? Data(contentsOf: filePath) {
                    if let decodingMedia = try? JSONDecoder().decode(DownloadedMedia.self, from: data) {
                        result.append(decodingMedia)
                    }
                }
            }
            return result
        }catch{
            return []
        }
        
        return []
    }
    
    //MARK: - Saving an episode
    //STEP ONE <Add the series info to series.keeinfo file>
    private func addSeries(_ info : Info){
        var list = (try? getSeriseListFile()) ?? []
        
        if let _ = list.first(where: {$0.id == info.id}){
                print("searise exists")
        }else{
            
            list.append(info)
            saveSeriseListFile(list)
        }
    }
    
    //STEP TWO <Create the required folders>
    private func checkFolders(forSerise: Info, andSeasonID: String){
        do{
//        if let g = downloadedMedia.group {
            let tvShowFolder = String(format: "%@/%@/%@",MediaManager.MediaType.series.version_3_value,userSignature, forSerise.id)
            if !checkFolderExistance(dir: tvShowFolder) {
                try fm.createDirectory(at: documentsDirectory.appendingPathComponent("DownloadCache")
                    .appendingPathComponent(tvShowFolder, isDirectory: true),
                                           withIntermediateDirectories: true)
            }
            
            let seasonFolder = String(format: "%@/%@",tvShowFolder, andSeasonID)
            
            if !checkFolderExistance(dir: seasonFolder) {
                try fm.createDirectory(at: documentsDirectory.appendingPathComponent("DownloadCache")
                    .appendingPathComponent(seasonFolder, isDirectory: true),
                                           withIntermediateDirectories: true)
            }
            
        } catch {
            
        }
        
    }
    
    //STEP THREE <Save the season info in the {seriseID}/seasons.keeinfo file>
    private func saveSeasonInfo(_ season: Info, forSerise s: String){
        var list = (try? getSeasonsListFile(forSerise: s)) ?? []
        if let _ = list.first(where: {$0.id == season.id}){
                print("season exists")
        }else{
            list.append(season)
            saveSeasonsListFile(list, atSerise: s)
        }
        
    }
    
    //STEP FOUR <Move the downloaded file to the {seriseID}/{seasonID}/{episodeID}.mp4 file>
    private func moveEpisodeFile(_ media: DownloadedMedia){
        guard let g = media.group else {return}
        let downloadPath = "\(MediaManager.MediaType.series.version_3_value)/\(userSignature)/\(g.showId)/\(g.seasonId)/\(g.episodeId)"
        
        do{
            try self.moveDownloadedFile(atPath: media.tempPath!,
                                        toCacheUsingName: downloadPath,
                                        Extension: "mp4")
            self.saveEpisodeInfo(media)
        }catch{
            print(error)
        }
        
        
    }
    
    //STEP FIVE <Save the episode info in {seriseID}/{seasonID}/{episodeID}.keeinfo file>
    private func saveEpisodeInfo(_ media: DownloadedMedia){
        guard let g = media.group else {return}
        let downloadPath = cache.appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true)
            .appendingPathComponent(userSignature)
            .appendingPathComponent(g.showId)
            .appendingPathComponent(g.seasonId)
            .appendingPathComponent(g.episodeId)
            .appendingPathExtension("keeinfo")
        
        if let data = try? JSONEncoder().encode(media){
            try? data.write(to: downloadPath)
        }
    }
}


//MARK: - Lists Store/Read Functions
extension FilesManager {
    //MARK: - Movies
    private func saveDMListContent(_ content: [String:DownloadedMedia]){
        if let data = try? JSONEncoder().encode(content){
            let dmListFile = cache.appendingPathComponent(MediaManager.MediaType.movie.version_3_value, isDirectory: true).appendingPathComponent(userSignature).appendingPathComponent("dmList.keeImportant")
            try? data.write(to: dmListFile)
        }
    }
    
    private func getDMList() throws ->[String:DownloadedMedia]{
        let dmListFile = cache.appendingPathComponent(MediaManager.MediaType.movie.version_3_value, isDirectory: true).appendingPathComponent(userSignature).appendingPathComponent("dmList.keeImportant")
        
        if checkFileExistance(filePath: dmListFile.path){
            let data = try Data(contentsOf: dmListFile)
                let dmListContent = try JSONDecoder().decode([String:DownloadedMedia].self, from: data)
                    return dmListContent
        }
        
        return [:]
    }
    
    //MARK: - Serise
    private func getSeriseListFile()throws->[Info]{
        let dmListFile = cache.appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true).appendingPathComponent(userSignature).appendingPathComponent("serise.keeinfo")
        if checkFileExistance(filePath: dmListFile.path){
            let data = try Data(contentsOf: dmListFile)
                let dmListContent = try JSONDecoder().decode([Info].self, from: data)
                    return dmListContent
        }
        return []
    }
    private func saveSeriseListFile(_ list: [Info]){
        if let data = try? JSONEncoder().encode(list){
            let dmListFile = cache.appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true).appendingPathComponent(userSignature).appendingPathComponent("serise.keeinfo")
            try? data.write(to: dmListFile)
        }
    }
    
    private func getSeasonsListFile(forSerise s: String)throws->[Info]{
        let dmListFile = cache.appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true).appendingPathComponent(userSignature).appendingPathComponent(s).appendingPathComponent("seasons.keeinfo")
        if checkFileExistance(filePath: dmListFile.path){
            let data = try Data(contentsOf: dmListFile)
                let dmListContent = try JSONDecoder().decode([Info].self, from: data)
                    return dmListContent
        }
        return []
        
    }
    
    private func saveSeasonsListFile(_ list: [Info], atSerise s: String){
        if let data = try? JSONEncoder().encode(list){
            let dmListFile = cache.appendingPathComponent(MediaManager.MediaType.series.version_3_value, isDirectory: true).appendingPathComponent(userSignature).appendingPathComponent(s).appendingPathComponent("seasons.keeinfo")
            try? data.write(to: dmListFile)
        }
    }
}


struct Info : Codable {
    var name : String
    var id : String
    var data: Data?
    
    var info : [String:Any]? {
        set{
            if newValue != nil{
                self.data = try? JSONSerialization.data(withJSONObject: newValue!, options: .prettyPrinted)
            }
        }
        
        get{
            if let data = self.data{
                return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String:Any]
            }
            return nil
        }
    }
}

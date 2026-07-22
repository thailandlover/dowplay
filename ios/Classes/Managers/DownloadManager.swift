//
//  DownloadManager.swift
//  KeeCustomPlayer
//
//  Created by Ahmed Qazzaz on 05/12/2022.
//

import UIKit



public class DownloadManager: NSObject/*, ObservableObject */{
    public static var shared = DownloadManager()
    public static var backgroundCompletionHandler : (() -> Void)?
    
    // Background session: used to resume downloads if the app is terminated by the system
    private var urlSession: URLSession!

    // Foreground session: used for active downloads while the app is open (full speed, no throttling)
    private var foregroundUrlSession: URLSession!

//    @Published var tasks: [URLSessionTask] = []
    var tasks: [URLSessionTask] = []
    
    private var configed : Bool = false
    private var settings : HostAppSettings!
    var didLoadPreListedTasks : (()->Void)?
    var userSignature : String {
        return settings.userSignature
    }
    
    override private init() {
        super.init()

        // --- Background URLSession ---
        // Kept for resuming downloads after app termination.
        // isDiscretionary is set to false so iOS does NOT throttle or defer transfers at its discretion.
        // isDiscretionary = true was the main cause of extremely slow download speeds.
        let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).background")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // --- Foreground URLSession ---
        // Used while the app is in the foreground. iOS does not throttle foreground sessions,
        // so downloads run at full available network speed.
        let foregroundConfig = URLSessionConfiguration.default
        foregroundConfig.allowsCellularAccess = true
        foregroundUrlSession = URLSession(configuration: foregroundConfig, delegate: self, delegateQueue: nil)

        updateTasks()
    }
    
    public func config(useSettings : HostAppSettings){
        self.settings = useSettings
        FilesManager.shared.setUser(userSignature)
        configed = true
        let tmpList = FilesManager.shared.getTempData(user: userSignature)
        for media in tmpList {
            if let tasId = media.reCallRequest() {
                FilesManager.shared.clearTempDataFor(id: tasId, user: userSignature)
            }
        }
    }

    @discardableResult
    public func startDownload(url: URL,
                              forMediaId id :Int,
                              mediaName: String = "",
                              type: MediaManager.MediaType,
                              mediaGroup: MediaGroup?,
                              object: [String:Any]? = nil,
                              shouldStart : Bool = true)->URLSessionDownloadTask?  {
        if !configed {return nil}
        if tasks.contains(where: {$0.currentRequest?.url == url}) {
            return nil
        }
        
        // Use the foreground session for immediate full-speed downloads while the app is open.
        // The background session is kept for resuming after app termination (handled by updateTasks).
        //let task = foregroundUrlSession.downloadTask(with: url)
        let task = urlSession.downloadTask(with: url)

        task.taskDescription = mediaName
        task.mediaId = "\(id)_\(type.version_3_value)_\(userSignature)" //mediaID format (3255_movie) or (36970_series)
        // countOfBytesClientExpectsToReceive removed: setting a fixed 5GB value caused iOS to
        // classify all downloads as very large transfers and apply additional throttling.
        // iOS will now determine the expected size automatically from the Content-Length header.
        if shouldStart{
            task.resume()
        }
        tasks.append(task)
        
        if let object = object, let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted){
            UserDefaults.standard.set(data, forKey: "\(id)_\(type.version_3_value)_\(userSignature)")
        }
        mediaGroup?.register()
        return task
    }

    func updateTasks() {
        urlSession.getAllTasks { tasks in
            DispatchQueue.main.async {
                self.tasks = tasks.filter({$0.state != .completed})
                self.didLoadPreListedTasks?()
            }
        }
    }
    
    public func saveDownloadStatus(){
        tasks.forEach({ task in
            if let downloadTask = task as? URLSessionDownloadTask{
                if(downloadTask != nil){
                    var media = self.extractMedia(usingTask: downloadTask)
                    if(media != nil){
                        if(task != nil && task.mediaId != nil && userSignature != nil && ((task.originalRequest?.url) != nil)){
                            media.saveDownloadStatus(taskId: task.mediaId!, signature: userSignature, url: task.originalRequest?.url)
                            task.cancel()
                        }
                    }
                }
            }
        }) 
    }
    
    //MARK: - Getting Download Task Progress
    
    func getAllDownloadingTasks(forType type : MediaManager.MediaType)->[URLSessionTask]{
        if !configed {return []}
        return tasks
    }
    
    func getDownloadTask(withMediaId id: String, forType type: MediaManager.MediaType)->URLSessionTask?{
        if !configed {return nil}
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        return tasks.first(where: {$0.mediaId == taskId})
    }
    
    public func getDownloadProgress(ForMediaId id: String, ofMediaType type: MediaManager.MediaType)->Double?{
        return getDownloadTask(withMediaId: id, forType: type)?.progress.fractionCompleted
    }
    
    
    public func getDownloadedMovie(_ id: String)-> DownloadedMedia?{
        if var completed = try? FilesManager.shared.getDownloadeMovieById(id){
            return completed.setUser(signature: userSignature)
        }
        
        if let task = getDownloadTask(withMediaId: id, forType: .movie) as? URLSessionDownloadTask{
            var media = extractMedia(usingTask: task)
            return media.setUser(signature: userSignature)
        }
        
        return nil
        
    }
    
    public func getDownloadedEpisode(_ id: String, seasonId: String, tvShowId: String)-> DownloadedMedia?{
        if let completed = FilesManager.shared.getDownloadedEpisode(id: id, season: seasonId, series: tvShowId){
            return completed
        }
        
        if let task = getDownloadTask(withMediaId: id, forType: .series) as? URLSessionDownloadTask{
            return extractMedia(usingTask: task)
        }
        
        return nil
        
    }
        
    //MARK: - Cancel Download Functions
    public func cancelAll(){
        if !configed {return}
        tasks.forEach({$0.cancel()})
        tasks.removeAll()
    }
    
    public func cancelMedia(withMediaId id: String,
                            seasonId : String? = nil,
                            showId : String? = nil,
                            forType type: MediaManager.MediaType){
        if !configed {return}
        do{
            if type == .movie {
                try FilesManager.shared.deleteMovieBy(id: id)
            }else {
                if let sId = seasonId, let tvId = showId {
                    FilesManager.shared.deleteEpisodeById(id, season: sId, series: tvId)
                }                
            }
        }catch{
            
        }
        
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        cancelTask(withID: taskId)
    }
    
    func cancelTask(withID id: String){
        if !configed {return}
        tasks.first(where: {$0.mediaId == id})?.cancel()
        tasks.removeAll(where: {$0.mediaId == id})
    }
    
    //MARK: - Pause Download Functions
    
    public func pauseDownloadForAllMedia(){
        if !configed {return}
        tasks.forEach({$0.suspend()})
    }
    
    public func pauseDownload(forMediaId id: String, ofType type: MediaManager.MediaType){
        if !configed {return}
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        pauseDownload(forTaskID: taskId)
    }
    
    func pauseDownload(forTaskID id: String){
        if !configed {return}
        tasks.first(where: {$0.mediaId == id})?.suspend()
    }
    
    //MARK: - Resume Download Functions
    public func resumeDownload(forMediaId id: String, ofType type: MediaManager.MediaType){
        if !configed {return}
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        resumeDownload(forTaskID: taskId)
    }
    
    func resumeDownload(forTaskID id: String){
        if !configed {return}
        tasks.first(where: {$0.mediaId == id})?.resume()
    }
    
    
    //MARK: - Check Download Status Functions
    ///is downloading regardless the status
    public func isDownloadingMediaWithID(_ id : String, ofType type: MediaManager.MediaType)->Bool{
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        return tasks.contains(where: {taskId == "\($0.mediaId ?? "")"})
    }
    
    ///is downloading and is suspended
    public func isDownloadingMediaWithIDSuspended(_ id : String, ofType type: MediaManager.MediaType)->Bool{
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        return tasks.first(where: {taskId == "\($0.mediaId ?? "")"})?.state == .suspended
    }
    
 
    public func movieIsDownloaded(_ id : String)->Bool {
        return (try? FilesManager.shared.getDownloadeMovieById(id) != nil) ?? false
    }
    
    public func episodeIsDownloaded(_ id : String, season: String, serise: String)->Bool {
        return (FilesManager.shared.getDownloadedEpisode(id: id, season: season, series: serise) != nil)
    }
    //MARK: - Hybrid Functions
    ///Get all media (downloading, suspended, and downloaded)
    public func getAllMedia() throws -> [DownloadedMedia]{
        guard configed else {throw DonwloadManagerError.managerIsNotConfiged}
        var allMedia : [DownloadedMedia] = []
        
        var allTasks =  tasks.map({ task in
            if let t = task as? URLSessionDownloadTask {
                return extractMedia(usingTask: t)
            }
            return nil
        }).compactMap({$0})
        allTasks = allTasks.filter({$0.object != nil || $0.status != .completed})
        let movieTasks = allTasks.filter({$0.mediaType == .movie})
        let seriseTasks = allTasks.filter({$0.mediaType == .series})
        let convrtedSeriseTasks = groupDownloadinTasksForSerise(tasksList: seriseTasks)
        
        allMedia.append(contentsOf: movieTasks)
        allMedia.append(contentsOf: convrtedSeriseTasks)
        
        var localMediaList = FilesManager.shared.getAllDownloadedMedia()
        localMediaList = localMediaList.filter({ item in
            print(item.mediaId)
            return !(allMedia.contains(where: {$0.mediaId == item.mediaId}))
        })
        
        
        allMedia.append(contentsOf: localMediaList)
        
        return allMedia
    }
    
    public func getAllMedia(ForSerise seriesID: String) throws -> [DownloadedMedia]{
        guard configed else {throw DonwloadManagerError.managerIsNotConfiged}
        var allMedia : [DownloadedMedia] = []
        allMedia.append(contentsOf: getDownloadingSeasons(forSerise: seriesID))
        
        var localMediaList = FilesManager.shared.getSeasons(forSeriseID: seriesID)
        localMediaList = localMediaList.filter({ item in
            print(item.mediaId)
            return !(allMedia.contains(where: {$0.mediaId == item.mediaId}))
        })
        
        allMedia.append(contentsOf:localMediaList)
        return allMedia
    }
    
    public func getAllEpisodes(forSeason sID: String, atSeriesID id: String)throws -> [DownloadedMedia] {
        guard configed else {throw DonwloadManagerError.managerIsNotConfiged}
        var allMedia : [DownloadedMedia] = []
        allMedia.append(contentsOf: getDownloadingEpisodes(inSeason: sID, forSerise: id))
        allMedia.append(contentsOf:FilesManager.shared.getEpisodes(seasonID: sID, atSeriseId: id))
        return allMedia
    }
    

    public func getAllMediaDecoded(sortKey : MediaSortKey = .id,
                                   sortOrder: OrderType = .asce)-> [[String:Any]] {
        return (try? self.getAllMedia().sortMedia(sortKey, type: sortOrder).getEncodedDictionary()) ?? []
    }
    
    public func getAllSeasonsDecoded(forSeries id: String,
                                     sortKey : MediaSortKey = .id,
                                     sortOrder: OrderType = .asce)-> [[String:Any]] {
        return (try? self.getAllMedia(ForSerise: id).sortMedia(sortKey, type: sortOrder).getEncodedDictionary()) ?? []
    }
    
    public func getAllEpisodesDecoded(forSeason sID: String,
                                      atSeriesID id: String,
                                      sortKey : MediaSortKey = .id,
                                      sortOrder: OrderType = .asce)-> [[String:Any]] {
        return (try? self.getAllEpisodes(forSeason: sID, atSeriesID: id).sortMedia(sortKey, type: sortOrder).getEncodedDictionary()) ?? []
    }
    
    
    func getDownloadingEpisodes(inSeason id: String, forSerise sid: String)->[DownloadedMedia] {
        var serise = tasks.filter({task in
            // 0 : id
            // 1 : type
            // 2 : user signature
            let pureType = task.mediaId?.components(separatedBy: "_")[1] ?? ""
            return pureType != "movies"
        }).map({task in
            if let t = task as? URLSessionDownloadTask {
                return extractMedia(usingTask: t)
            }
            return nil
        }).compactMap({$0})
        serise = serise.filter({$0.object != nil || $0.status != .completed})
        let episodes = serise.filter({ item in
            return item.group?.seasonId == id && item.group?.showId == sid
        })
        
        return episodes
    }
    
    func getDownloadingSeasons(forSerise id: String)->[DownloadedMedia]{
        // 0 : id
        // 1 : type
        // 2 : user signature
        var serise = tasks.filter({task in
            let pureType = task.mediaId?.components(separatedBy: "_")[1] ?? ""
            return pureType != "movies"
        }).map({task in
            if let t = task as? URLSessionDownloadTask {
                let media = extractMedia(usingTask: t)
                return media.group?.showId == id ? media : nil
            }
            return nil
        }).compactMap({$0})
        serise = serise.filter({$0.object != nil || $0.status != .completed})
        
        var seasons : [String: DownloadedMedia] = [:]
        for e in serise { // the content here is eposiods
            if let g = e.group{
                let dm = DownloadedMedia(mediaId: g.seasonId, name: g.seasonName, group: g, type: .SeasonInfo)
                if seasons[g.seasonId] == nil {
                    seasons[g.seasonId] = dm
                }
            }
        }
        
        return Array(seasons.values)
    }
    
    func groupDownloadinTasksForSerise(tasksList : [DownloadedMedia])->[DownloadedMedia]{
        var serises : [String: DownloadedMedia] = [:]
        for t in tasksList {
            if let g = t.group{
                let dm = DownloadedMedia(mediaId: g.showId, name: g.showName, group: g, type: .SeriseInfo)
                if serises[g.showId] == nil {
                    serises[g.showId] = dm
                }
            }
        }
        return Array(serises.values)
    }
   
    
    
    func extractMedia(usingTask task : URLSessionDownloadTask)->DownloadedMedia{
        // 0 : id
        // 1 : type
        // 2 : user signature
        let  pureID = task.mediaId?.components(separatedBy: "_").first
        let pureType = task.mediaId?.components(separatedBy: "_")[1]
        
        var obj = DownloadedMedia(mediaId: pureID ?? "", name: task.taskDescription ?? "Untitled Media", status: task.state, progress: task.progress.fractionCompleted)
        
        if pureType != "movies"{
            obj.mediaType = .series
            obj.mediaRetrivalType = .EpisodeInfo
        }
        
        if let data = UserDefaults.standard.object(forKey: "\(task.mediaId ?? "")") as? Data,
           let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String:Any]{
            obj.object = object
        }
        if let  pureID = pureID {
            obj.group = MediaGroup.get(usingEpisodeID: pureID)
        }
        
        return obj
    }
}

extension DownloadManager: URLSessionDelegate, URLSessionDownloadDelegate {
    public func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten _: Int64, totalBytesExpectedToWrite _: Int64) {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "downloadTask_media"), object: downloadTask)
        if let id = downloadTask.mediaId {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "downloadTask_media_\(id)"), object: downloadTask)
        }
    }

    public func urlSession(_: URLSession, downloadTask d: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 0 : id
        // 1 : type
        // 2 : user signature
        let  pureID = d.mediaId?.components(separatedBy: "_").first
        let pureType = d.mediaId?.components(separatedBy: "_")[1]
        
        var obj = DownloadedMedia(mediaId: pureID ?? "", name: d.taskDescription ?? "Untitled Media", tempPath: location)
        
        if pureType != "movies"{
            obj.mediaType = .series
            obj.mediaRetrivalType = .EpisodeInfo
        }
        
        if let data = UserDefaults.standard.object(forKey: "\(d.mediaId ?? "")") as? Data,
           let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String:Any]{
            obj.object = object
            UserDefaults.standard.removeObject(forKey: "\(d.mediaId ?? "")")            
        }
        if let  pureID = pureID {
            let group = MediaGroup.get(usingEpisodeID: pureID)
            obj.group = group
            UserDefaults.standard.removeObject(forKey: "\(d.mediaId ?? "")_group")
        }
        
        do{
            try obj.store(signature: userSignature)
            
        }catch{
            print("Error:\(error)")
        }
            
        print("finished")
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
               guard let backgroundCompletionHandler =
                   DownloadManager.backgroundCompletionHandler else {
                       return
               }
               backgroundCompletionHandler()
           }
    }

    // public func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    //     task.mediaId = nil
    //     if let error = error {
    //         print("error : \(error)")
    //     } else {
    //         print("Finish")
    //     }
    // }
    public func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
        print("error : \(error)")
        return
    }

    task.mediaId = nil
    print("Finish")
}
    
    
    
    
}



extension URLSessionTask {
    var mediaId : String?{
        set(value){
            if let value = value {
                UserDefaults.standard.set(value, forKey: "task_id_\(taskIdentifier)")
            }else{
                UserDefaults.standard.removeObject(forKey: "task_id_\(taskIdentifier)")
            }
        }
        get{
            return UserDefaults.standard.object(forKey: "task_id_\(taskIdentifier)") as? String
        }
    }
}

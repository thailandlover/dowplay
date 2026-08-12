//
//  DownloadManager.swift
//  KeeCustomPlayer
//
//  Created by Ahmed Qazzaz on 05/12/2022.
//

import UIKit
import Network



public class DownloadManager: NSObject/*, ObservableObject */{
    public static var shared = DownloadManager()
    public static var backgroundCompletionHandler : (() -> Void)?

    /// Every transfer runs on this background session. It is the only session type iOS keeps
    /// alive while the app is suspended, that retries by itself when connectivity drops, and
    /// that hands its tasks back when the app is launched again.
    private var urlSession: URLSession!

    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.dowplay.download.network")
    private var networkIsAvailable = true

    private static let firstRetryDelay : TimeInterval = 10
    private static let maxRetryDelay : TimeInterval = 300
    private var retryDelay : TimeInterval = DownloadManager.firstRetryDelay
    private var retryWorkItem : DispatchWorkItem?

    /// How often a running transfer is checked for being stuck. Shortened by the test suite.
    static var stallCheckInterval : TimeInterval = 30
    private var receivedBytes : [Int : Int64] = [:]
    private var idleChecks : [Int : Int] = [:]

    /// How many transfers run at the same time. The bandwidth is the same whatever this number is,
    /// so keeping it low only changes which media finishes first: with three at a time the user
    /// can start watching the first episode much sooner than with all of them crawling together.
    static let maxActiveDownloads = 3
    /// Media that just failed or was found stuck, and should not take a slot again right away.
    private var deferredUntil : [String : Date] = [:]

    private var activeDownloads : Int {
        return tasks.filter({$0.state == .running}).count
    }

//    @Published var tasks: [URLSessionTask] = []
    var tasks: [URLSessionTask] = []

    private var configed : Bool = false
    private var settings : HostAppSettings!
    var didLoadPreListedTasks : (()->Void)?
    var userSignature : String {
        return settings?.userSignature ?? ""
    }

    static var backgroundSessionIdentifier : String {
        return sessionIdentifierOverride ?? "\(Bundle.main.bundleIdentifier ?? "com.dowplay").background"
    }

    /// Set by the test suite only. A process cannot rebuild a background session with an
    /// identifier it has already invalidated, so each simulated launch gets its own identifier.
    static var sessionIdentifierOverride : String?

    /// An invalidated session throws when it is asked for a task, and it keeps delivering the
    /// callbacks of the transfers it cancelled, so nothing must be started on it any more.
    private var sessionIsInvalid = false

    override private init() {
        super.init()

        // isDiscretionary = false keeps iOS from deferring or throttling the transfers,
        // isDiscretionary = true was the main cause of extremely slow download speeds.
        let config = URLSessionConfiguration.background(withIdentifier: DownloadManager.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        updateTasks()
        startNetworkMonitoring()
        scheduleStallCheck()
    }

    public func config(useSettings : HostAppSettings){
        self.settings = useSettings
        FilesManager.shared.setUser(userSignature)
        configed = true

        // Restore only after the session reported which transfers it is still running,
        // otherwise a restore would start a second copy of a download that is already live.
        updateTasks { [weak self] in
            self?.restorePendingDownloads()
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
        guard !sessionIsInvalid, DownloadManager.shared === self else {return nil}
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)" //mediaID format (3255_movie_12_34) or (36970_series_12_34)

        // Match on the media id too: the same media can come back with a freshly signed URL.
        if tasks.contains(where: {$0.mediaId == taskId || $0.originalRequest?.url == url}) {
            return nil
        }

        // Keep the payload and the group reachable whenever the transfer actually starts.
        if let object = object, let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted){
            UserDefaults.standard.set(data, forKey: taskId)
        }
        mediaGroup?.register()

        // Only a few transfers run at a time. The rest wait as records, which is what keeps them
        // in the list, in order, and startable as soon as a slot frees.
        guard !shouldStart || activeDownloads < DownloadManager.maxActiveDownloads else {
            queueDownload(taskId: taskId, mediaId: "\(id)", name: mediaName,
                          type: type, url: url, group: mediaGroup, object: object)
            return nil
        }

        let task : URLSessionDownloadTask
        if let resumeData = FilesManager.shared.getResumeData(id: taskId, user: userSignature) {
            // Continue from the bytes iOS already handed back instead of starting over.
            task = urlSession.downloadTask(withResumeData: resumeData)
            FilesManager.shared.clearResumeData(id: taskId, user: userSignature)
        } else {
            task = urlSession.downloadTask(with: url)
        }

        task.setMediaIdentity(mediaId: taskId, mediaName: mediaName)
        // countOfBytesClientExpectsToReceive is not set: a fixed 5GB value made iOS treat every
        // download as a very large transfer and throttle it further. iOS reads the real size
        // from the Content-Length header instead.
        if shouldStart{
            task.resume()
        }
        tasks.append(task)
        deferredUntil[taskId] = nil
        // Persist the download before anything else can go wrong: this record is what keeps the
        // media in the list (and restartable) if the app is killed or the transfer dies.
        persistRecord(for: task, url: url, status: shouldStart ? .running : .suspended)
        return task
    }

    func updateTasks(completion: (()->Void)? = nil) {
        urlSession.getAllTasks { sessionTasks in
            DispatchQueue.main.async {
                // A task that is being cancelled is on its way out and must not come back to the
                // list, so only the running and paused ones are kept.
                let live = sessionTasks.filter({$0.state == .running || $0.state == .suspended})
                let liveIdentifiers = Set(live.map({$0.taskIdentifier}))
                // Keep the tasks this launch created that the session has not listed yet,
                // instead of replacing the whole list and losing them.
                let untracked = self.tasks.filter({ !liveIdentifiers.contains($0.taskIdentifier) && ($0.state == .running || $0.state == .suspended) })
                self.tasks = live + untracked
                self.recoverMissingIdentities()
                self.didLoadPreListedTasks?()
                completion?()
            }
        }
    }

    /// Re-attaches a media id to any restored task that lost it, by matching the URL against the
    /// persisted records. Without it such a task would show up as an unnamed, unusable entry.
    private func recoverMissingIdentities() {
        let unidentified = tasks.filter({$0.mediaId == nil})
        guard !unidentified.isEmpty, configed else {return}
        let records = FilesManager.shared.getTempData(user: userSignature)
        for task in unidentified {
            guard let url = task.originalRequest?.url ?? task.currentRequest?.url else {continue}
            guard let record = records.first(where: {$0.mediaURL == url}) else {continue}
            task.setMediaIdentity(mediaId: "\(record.mediaId)_\(record.mediaType.version_3_value)_\(userSignature)",
                                  mediaName: record.name)
        }
    }

    /// Restarts every persisted download that has no live task behind it: the app was force
    /// quit, or the transfer died while the app was closed. Whatever does not fit in the running
    /// slots simply stays a record and waits its turn.
    func restorePendingDownloads() {
        guard configed else {return}
        for media in recordsInQueueOrder() {
            if isDownloadingMediaWithID(media.mediaId, ofType: media.mediaType) {continue}
            _ = media.reCallRequest()
        }
    }

    /// Starts the media that has waited the longest, as soon as a slot is free.
    private func startNextInQueue() {
        guard configed, activeDownloads < DownloadManager.maxActiveDownloads else {return}
        let signature = userSignature
        let waiting = recordsInQueueOrder().filter({ record in
            // A media the user paused waits for the user, and one that just failed waits for its
            // delay to pass, so neither takes a slot from a media that can transfer right now.
            record.retrivalStatus != URLSessionTask.State.suspended.rawValue
                && !isDownloadingMediaWithID(record.mediaId, ofType: record.mediaType)
                && isReadyToStart(record, signature: signature)
        })
        guard let next = waiting.first else {return}
        _ = next.reCallRequest()
    }

    /// The persisted downloads, oldest request first.
    private func recordsInQueueOrder() -> [DownloadedMedia] {
        let signature = userSignature
        return FilesManager.shared.getTempData(user: signature).sorted(by: { first, second in
            let firstDate = FilesManager.shared.tempDataDate(id: taskId(of: first, signature: signature), user: signature) ?? Date.distantPast
            let secondDate = FilesManager.shared.tempDataDate(id: taskId(of: second, signature: signature), user: signature) ?? Date.distantPast
            return firstDate < secondDate
        })
    }

    private func taskId(of record: DownloadedMedia, signature: String) -> String {
        return "\(record.mediaId)_\(record.mediaType.version_3_value)_\(signature)"
    }

    private func isReadyToStart(_ record: DownloadedMedia, signature: String) -> Bool {
        guard let waitUntil = deferredUntil[taskId(of: record, signature: signature)] else {return true}
        return Date() >= waitUntil
    }

    /// Sends a media to the back of the queue for a while, so a transfer that keeps failing or
    /// stalling cannot hold a slot against media that can actually run.
    private func deferFromQueue(taskId: String, by delay: TimeInterval) {
        deferredUntil[taskId] = Date().addingTimeInterval(delay)
    }

    /// Writes the record of a media that has to wait, without creating a task for it.
    private func queueDownload(taskId: String, mediaId: String, name: String,
                               type: MediaManager.MediaType, url: URL,
                               group: MediaGroup?, object: [String:Any]?) {
        // An earlier attempt already left a record holding the progress it reached: leave it be.
        guard FilesManager.shared.getTempData(id: taskId, user: userSignature) == nil else {return}

        var media = DownloadedMedia(mediaId: mediaId, name: name, status: .running, progress: 0)
        if type != .movie {
            media.mediaType = .series
            media.mediaRetrivalType = .EpisodeInfo
        }
        media.object = object
        media.group = group ?? MediaGroup.get(usingEpisodeID: mediaId)
        media.saveDownloadStatus(taskId: taskId, signature: userSignature, url: url)
    }

    /// A transfer died, so try again after a while: a short outage should not leave the download
    /// waiting until the user opens the app again. The delay grows with every failure in a row.
    /// The delay only goes back to its floor once something finishes, never when a transfer is
    /// (re)started: a retry goes through startDownload too, and resetting there would keep a link
    /// that always fails retrying every ten seconds for as long as the app is open.
    private func scheduleRetry() {
        guard configed else {return}
        retryWorkItem?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, DownloadManager.maxRetryDelay)

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.configed else {return}
            self.restorePendingDownloads()
            self.startNextInQueue()
            // Keep sweeping while something is still waiting to be picked up.
            if !FilesManager.shared.getTempData(user: self.userSignature).isEmpty {
                self.scheduleRetry()
            }
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// After a connection is lost iOS can leave a transfer waiting for a very long time, even once
    /// the network is back, without ever reporting an error. A transfer that has not received a
    /// single byte for two checks in a row is therefore restarted from its resume data.
    private func scheduleStallCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + DownloadManager.stallCheckInterval) { [weak self] in
            guard let self = self else {return}
            self.restartStalledTasks()
            self.scheduleStallCheck()
        }
    }

    private func restartStalledTasks() {
        guard configed, networkIsAvailable else {return}

        for task in tasks where task.state == .running {
            let identifier = task.taskIdentifier
            let received = task.countOfBytesReceived
            if receivedBytes[identifier] == received {
                idleChecks[identifier] = (idleChecks[identifier] ?? 0) + 1
            } else {
                receivedBytes[identifier] = received
                idleChecks[identifier] = 0
            }

            guard (idleChecks[identifier] ?? 0) >= 2 else {continue}
            idleChecks[identifier] = 0
            restartStalled(task)
        }

        let known = Set(tasks.map({$0.taskIdentifier}))
        receivedBytes = receivedBytes.filter({known.contains($0.key)})
        idleChecks = idleChecks.filter({known.contains($0.key)})
    }

    private func restartStalled(_ task: URLSessionTask) {
        guard let downloadTask = task as? URLSessionDownloadTask, let taskId = task.mediaId else {return}
        let signature = task.mediaSignature ?? userSignature
        guard !signature.isEmpty else {return}
        let identifier = task.taskIdentifier
        print("restarting stalled download \(taskId)")

        downloadTask.cancel(byProducingResumeData: { data in
            if let data = data {
                FilesManager.shared.saveResumeData(data, id: taskId, user: signature)
            }
            DispatchQueue.main.async {
                self.tasks.removeAll(where: {$0.taskIdentifier == identifier})
                // Back of the queue: a media that keeps stalling must not hold a slot against the
                // ones that can transfer.
                self.deferFromQueue(taskId: taskId, by: DownloadManager.firstRetryDelay)
                self.startNextInQueue()
            }
        })
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else {return}
            let isAvailable = path.status == .satisfied
            let recovered = isAvailable && !self.networkIsAvailable
            self.networkIsAvailable = isAvailable
            guard recovered else {return}
            // Connectivity is back: pick up whatever the session gave up on while it was gone.
            DispatchQueue.main.async {
                self.restorePendingDownloads()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    /// Writes the on-disk record used to rebuild the list and to restart the transfer.
    private func persistRecord(for task: URLSessionTask, url: URL? = nil, status: URLSessionTask.State? = nil) {
        guard let taskId = task.mediaId else {return}
        let signature = task.mediaSignature ?? userSignature
        guard !signature.isEmpty else {return}
        guard let downloadTask = task as? URLSessionDownloadTask else {return}
        var media = extractMedia(usingTask: downloadTask)
        media.status = status ?? task.state
        media.saveDownloadStatus(taskId: taskId,
                                 signature: signature,
                                 url: url ?? task.originalRequest?.url ?? task.currentRequest?.url)
    }

    /// Drops every trace of an in-flight download: its record, its resume data and its payload.
    private func clearRecord(forTaskId taskId: String, signature: String) {
        guard !signature.isEmpty else {return}
        FilesManager.shared.clearTempDataFor(id: taskId, user: signature)
        FilesManager.shared.clearResumeData(id: taskId, user: signature)
    }

    public func saveDownloadStatus(){
        tasks.forEach({ task in
            persistRecord(for: task)
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

        if var pending = pendingRecords().first(where: {$0.mediaId == id && $0.mediaType == .movie}).map({asListEntry($0)}) {
            return pending.setUser(signature: userSignature)
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

        if let pending = pendingRecords().first(where: {$0.mediaId == id && $0.mediaType == .series}) {
            return asListEntry(pending)
        }

        return nil

    }

    //MARK: - Cancel Download Functions
    public func cancelAll(){
        if !configed {return}
        let signature = userSignature
        tasks.forEach({ task in
            if let taskId = task.mediaId {
                clearRecord(forTaskId: taskId, signature: signature)
            }
            task.cancel()
        })
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
        // Clear the record first: the cancellation callback must not resurrect the download.
        clearRecord(forTaskId: id, signature: userSignature)
        UserDefaults.standard.removeObject(forKey: id)
        deferredUntil[id] = nil
        tasks.first(where: {$0.mediaId == id})?.cancel()
        tasks.removeAll(where: {$0.mediaId == id})
        startNextInQueue()
    }

    //MARK: - Pause Download Functions

    public func pauseDownloadForAllMedia(){
        if !configed {return}
        tasks.forEach({ task in
            task.suspend()
            persistRecord(for: task, status: .suspended)
        })
    }

    public func pauseDownload(forMediaId id: String, ofType type: MediaManager.MediaType){
        if !configed {return}
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        pauseDownload(forTaskID: taskId)
    }

    func pauseDownload(forTaskID id: String){
        if !configed {return}
        guard let task = tasks.first(where: {$0.mediaId == id}) else {
            // Nothing live to pause: the media is waiting in the queue, so mark its record.
            if var record = pendingRecords().first(where: {taskId(of: $0, signature: userSignature) == id}) {
                record.retrivalStatus = URLSessionTask.State.suspended.rawValue
                FilesManager.shared.saveTempData(id: id, data: record, user: userSignature)
            }
            return
        }
        task.suspend()
        // Remember the paused state so a restart after a relaunch does not resume it.
        persistRecord(for: task, status: .suspended)
        startNextInQueue()
    }

    //MARK: - Resume Download Functions
    public func resumeDownload(forMediaId id: String, ofType type: MediaManager.MediaType){
        if !configed {return}
        let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"
        resumeDownload(forTaskID: taskId)
    }

    func resumeDownload(forTaskID id: String){
        if !configed {return}
        guard let task = tasks.first(where: {$0.mediaId == id}) else {
            // Nothing live to resume: the transfer died while the app was away, restart it.
            if var record = pendingRecords().first(where: {"\($0.mediaId)_\($0.mediaType.version_3_value)_\(userSignature)" == id}) {
                // The record may be marked as paused, and the app is asking for it to run again.
                record.retrivalStatus = URLSessionTask.State.running.rawValue
                _ = record.reCallRequest()
            }
            return
        }
        task.resume()
        persistRecord(for: task, status: .running)
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

    /// Persisted downloads that are not represented by a live task.
    private func pendingRecords() -> [DownloadedMedia] {
        guard configed else {return []}
        return FilesManager.shared.getTempData(user: userSignature).filter({ record in
            !self.isDownloadingMediaWithID(record.mediaId, ofType: record.mediaType)
        })
    }

    /// A record keeps the information needed to restart the transfer, which a live task does not
    /// carry. The app must receive the same payload for a media wherever the entry came from, so
    /// those extra fields are dropped on the way out.
    private func asListEntry(_ record: DownloadedMedia) -> DownloadedMedia {
        var entry = record
        entry.mediaURL = nil
        entry.retrivalStatus = nil
        return entry
    }

    /// Everything that is still being downloaded: the live tasks plus the persisted records the
    /// session no longer knows about (force quit, transfer dropped while the app was closed).
    private func downloadingMedia() -> [DownloadedMedia] {
        var media = tasks.compactMap({ task in
            return (task as? URLSessionDownloadTask).map({extractMedia(usingTask: $0)})
        })
        media = media.filter({$0.object != nil || $0.status != .completed})
        media.append(contentsOf: pendingRecords().filter({ record in
            !media.contains(where: {$0.mediaId == record.mediaId && $0.mediaType == record.mediaType})
        }).map({ asListEntry($0) }))
        return media
    }

    ///Get all media (downloading, suspended, and downloaded)
    public func getAllMedia() throws -> [DownloadedMedia]{
        guard configed else {throw DonwloadManagerError.managerIsNotConfiged}
        var allMedia : [DownloadedMedia] = []

        let allTasks = downloadingMedia()
        let movieTasks = allTasks.filter({$0.mediaType == .movie})
        let seriseTasks = allTasks.filter({$0.mediaType == .series})
        let convrtedSeriseTasks = groupDownloadinTasksForSerise(tasksList: seriseTasks)

        allMedia.append(contentsOf: movieTasks)
        allMedia.append(contentsOf: convrtedSeriseTasks)

        var localMediaList = FilesManager.shared.getAllDownloadedMedia()
        localMediaList = localMediaList.filter({ item in
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
        return downloadingMedia().filter({ item in
            return item.mediaType == .series && item.group?.seasonId == id && item.group?.showId == sid
        })
    }

    func getDownloadingSeasons(forSerise id: String)->[DownloadedMedia]{
        let serise = downloadingMedia().filter({$0.mediaType == .series && $0.group?.showId == id})

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
        // 2... : user signature
        let  pureID = task.mediaId?.components(separatedBy: "_").first
        let pureType = task.mediaType
        let name = task.mediaName.isEmpty ? "Untitled Media" : task.mediaName

        var obj = DownloadedMedia(mediaId: pureID ?? "", name: name, status: task.state, progress: task.progress.fractionCompleted)

        if pureType != .movie{
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

    //MARK: - Testing Support

    /// Rebuilds the manager from scratch the way a killed and restarted app does: nothing is left
    /// in memory and the previous transfers are gone. Used by the test suite only.
    static func simulateAppRelaunch(completion: @escaping ()->Void) {
        let previous = shared
        previous.sessionIsInvalid = true
        previous.networkMonitor.cancel()
        previous.urlSession.invalidateAndCancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            sessionIdentifierOverride = "\(Bundle.main.bundleIdentifier ?? "com.dowplay").background.test.\(UUID().uuidString)"
            shared = DownloadManager()
            completion()
        }
    }

    /// Forgets the configuration the way a process that iOS relaunched in the background has not
    /// received it yet, keeping the session and its delegate alive. Used by the test suite only.
    func forgetConfiguration() {
        settings = nil
        configed = false
        tasks.removeAll()
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
        // A 4xx/5xx body is an error page, not the media. Storing it would leave the user with a
        // media that looks downloaded and does not play, so keep the download pending instead.
        if let response = d.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            print("download answered with status \(response.statusCode)")
            let failedIdentifier = d.taskIdentifier
            let stillWanted = (d.mediaId.map({ FilesManager.shared.hasTempData(id: $0, user: d.mediaSignature ?? userSignature) })) ?? false
            DispatchQueue.main.async {
                self.tasks.removeAll(where: {$0.taskIdentifier == failedIdentifier})
                // Paused, not running: the link is refused rather than unreachable, so it is only
                // worth trying again when the app asks for this media again.
                if stillWanted {
                    self.persistRecord(for: d, status: .suspended)
                }
            }
            return
        }

        // 0 : id
        // 1 : type
        // 2... : user signature
        let  pureID = d.mediaId?.components(separatedBy: "_").first
        let pureType = d.mediaType
        // iOS can relaunch the app in the background to deliver this callback, long before
        // Flutter calls config_downloader. Read the owner from the task itself so the file is
        // never stored under an empty signature (which made it invisible to the app).
        let signature = d.mediaSignature ?? userSignature
        let name = d.mediaName.isEmpty ? "Untitled Media" : d.mediaName

        var obj = DownloadedMedia(mediaId: pureID ?? "", name: name, tempPath: location)

        if pureType != .movie{
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
            try obj.store(signature: signature)

        }catch{
            print("Error:\(error)")
        }

        // The media lives on disk now, so its in-flight bookkeeping can go.
        if let taskId = d.mediaId {
            clearRecord(forTaskId: taskId, signature: signature)
        }
        let finishedIdentifier = d.taskIdentifier
        DispatchQueue.main.async {
            self.tasks.removeAll(where: {$0.taskIdentifier == finishedIdentifier})
            self.retryDelay = DownloadManager.firstRetryDelay
            self.deferredUntil[d.mediaId ?? ""] = nil
            self.startNextInQueue()
        }
    }

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        sessionIsInvalid = true
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
               guard let backgroundCompletionHandler =
                   DownloadManager.backgroundCompletionHandler else {
                       return
               }
               DownloadManager.backgroundCompletionHandler = nil
               backgroundCompletionHandler()
           }
    }

    public func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else {
            print("Finish")
            return
        }
        print("error : \(error)")

        guard let taskId = task.mediaId else {return}
        let signature = task.mediaSignature ?? userSignature
        guard !signature.isEmpty else {return}

        let failedIdentifier = task.taskIdentifier

        // A media the app cancelled has no record left, and must not be brought back to life.
        guard let record = FilesManager.shared.getTempData(id: taskId, user: signature) else {
            DispatchQueue.main.async {
                self.tasks.removeAll(where: {$0.taskIdentifier == failedIdentifier})
            }
            return
        }

        // Keep the record so the media stays in the list and is picked up again by
        // restorePendingDownloads(), but never turn a download the user paused back on.
        let wasPaused = record.retrivalStatus == URLSessionTask.State.suspended.rawValue
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        DispatchQueue.main.async {
            self.tasks.removeAll(where: {$0.taskIdentifier == failedIdentifier})
            // A restart of this media may already be running (a stalled transfer is cancelled on
            // purpose), and its state must not be overwritten by the one that just died.
            guard !self.tasks.contains(where: {$0.mediaId == taskId}) else {return}

            if let resumeData = resumeData {
                FilesManager.shared.saveResumeData(resumeData, id: taskId, user: signature)
            }
            self.persistRecord(for: task, status: wasPaused ? .suspended : .running)
            if !wasPaused {
                self.deferFromQueue(taskId: taskId, by: self.retryDelay)
                self.scheduleRetry()
            }
            self.startNextInQueue()
        }
    }




}



/// The media identity is kept inside `taskDescription` because URLSession restores it together
/// with the task when the app is relaunched. The previous UserDefaults key was built from
/// `taskIdentifier`, which is only unique inside a single session and is reused across launches,
/// so records could be read, overwritten or erased for the wrong media.
private let mediaIdentitySeparator = "\u{1F}"

extension URLSessionTask {

    func setMediaIdentity(mediaId: String, mediaName: String) {
        taskDescription = mediaId + mediaIdentitySeparator + mediaName
    }

    var mediaId : String?{
        set(value){
            if let value = value {
                setMediaIdentity(mediaId: value, mediaName: mediaName)
            }else{
                taskDescription = mediaName
                UserDefaults.standard.removeObject(forKey: "task_id_\(taskIdentifier)")
            }
        }
        get{
            if let description = taskDescription,
               let separator = description.range(of: mediaIdentitySeparator) {
                return String(description[..<separator.lowerBound])
            }
            // Tasks created by an older version of the library kept their id here.
            return UserDefaults.standard.object(forKey: "task_id_\(taskIdentifier)") as? String
        }
    }

    var mediaName : String {
        guard let description = taskDescription else {return ""}
        if let separator = description.range(of: mediaIdentitySeparator) {
            return String(description[separator.upperBound...])
        }
        return description
    }

    /// mediaId format is `<mediaId>_<type>_<userId>_<profileId>`, the signature being the
    /// `<userId>_<profileId>` tail.
    var mediaSignature : String? {
        guard let components = mediaId?.components(separatedBy: "_"), components.count > 2 else {return nil}
        return components[2...].joined(separator: "_")
    }

    var mediaType : MediaManager.MediaType {
        let components = mediaId?.components(separatedBy: "_") ?? []
        guard components.count > 1 else {return .movie}
        return components[1] == MediaManager.MediaType.movie.version_3_value ? .movie : .series
    }
}

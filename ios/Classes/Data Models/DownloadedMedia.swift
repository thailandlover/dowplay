//
//  DownloadedMedia.swift
//  KeeCustomPlayer
//
//  Created by Ahmed Qazzaz on 05/03/2023.
//

import Foundation

enum MediaRetrivalType : String, Codable{
    case SeriseInfo = "SeriseInfo"
    case SeasonInfo = "SeasonInfo"
    case EpisodeInfo = "EpisodeInfo"
    case MovieInfo = "MovieInfo"
}

public struct DownloadedMedia : Codable{
    var mediaRetrivalType : MediaRetrivalType = .MovieInfo
    var signature : String = ""
    var mediaId : String
    var mediaURL : URL?
    var mediaType : MediaManager.MediaType = .movie
    var path : URL{
        if let g = group {
            return FilesManager.shared.cache.appendingPathComponent(mediaType.version_3_value, isDirectory: true)
                .appendingPathComponent(signature, isDirectory: true)
                .appendingPathComponent(g.showId, isDirectory: true)
                .appendingPathComponent(g.seasonId, isDirectory: true)
                .appendingPathComponent("\(mediaId).mp4")
        }
        
        return FilesManager.shared.cache.appendingPathComponent(mediaType.version_3_value, isDirectory: true).appendingPathComponent(signature, isDirectory: true).appendingPathComponent("\(mediaId).mp4")
    }
    var episodeInfoPathURL : URL?{
        if self.mediaType == .series && self.mediaRetrivalType == .EpisodeInfo {
            if let g = group {
                return FilesManager.shared.cache.appendingPathComponent(mediaType.version_3_value, isDirectory: true)
                    .appendingPathComponent(signature, isDirectory: true)
                    .appendingPathComponent(g.showId, isDirectory: true)
                    .appendingPathComponent(g.seasonId, isDirectory: true)
                    .appendingPathComponent("\(mediaId).keeinfo")                
            }
        }
        return nil
    }
    
    var name : String
    var tempPath : URL?
    var group : MediaGroup?
    private var data : Data?
    var object : [String:Any]? {
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
    
    var seasons : [Season] = []
    
    //Use only if the media is not downloaded yet (in progress)
    var status : URLSessionTask.State = .completed
    var retrivalStatus : Int?
    var progress : Double = 1
    
    enum CodingKeys: CodingKey {
        case mediaId
        case mediaURL
        case mediaType
        case name
        case tempPath
        case group
        case data
        case progress
        case mediaRetrivalType
        case retrivalStatus
    }
    
    init(mediaId: String, mediaURL: URL? = nil, mediaType: MediaManager.MediaType = .movie, name: String, tempPath: URL?) {
        self.mediaId = mediaId
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        self.name = name
        self.tempPath = tempPath
    }
    
    init(mediaId: String, mediaURL: URL? = nil, mediaType: MediaManager.MediaType = .movie, name: String, status : URLSessionTask.State, progress : Double) {
        self.mediaId = mediaId
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        self.name = name
        self.status = status
        self.progress = progress

    }
    
    init(mediaId: String, mediaURL: URL? = nil, mediaType: MediaManager.MediaType = .movie, name: String, group: MediaGroup, type : MediaRetrivalType) {
        self.mediaId = mediaId
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        self.name = name
        self.tempPath = nil
        self.group = group
        self.mediaRetrivalType = type
        
        if mediaRetrivalType != .MovieInfo {
            self.mediaType = .series
        }else{
            self.mediaType = .movie
        }
    }
    
    func reCallRequest()->String?{
        if let url = mediaURL {
            if let task = DownloadManager.shared.startDownload(url: url,
                                                 forMediaId: Int(mediaId) ?? 0,
                                                 mediaName: name,
                                                 type: mediaType,
                                                 mediaGroup: group,
                                                               object: object,
            shouldStart: !(retrivalStatus == 1)){
                return task.mediaId
            }
        }
        return nil
    }
   
    
//    var mediaDownloadName : String {
//        return mediaType.rawValue + "/" + "\(mediaId)"
//    }
    
    @discardableResult
    mutating func setUser(signature: String)->DownloadedMedia {
        self.signature = signature
        return self
    }
    
    mutating func saveDownloadStatus(taskId: String, signature: String, url: URL?){
        self.retrivalStatus = status.rawValue
        self.mediaURL = url
        FilesManager.shared.saveTempData(id: taskId, data: self, user: signature)
    }
    
    func store(signature: String) throws{
        try FilesManager.shared.forUser(signature).registerDownloadedMedia(self)
    }
    
    func remove(signature: String) throws{
        if mediaType == .movie{
            try FilesManager.shared.forUser(signature).deleteMovieBy(id: mediaId)
        }else{
            FilesManager.shared.forUser(signature).deleteEpisode(self)
        }
        
    }
    
    static func getMovieByID(id : String, signature: String)throws->DownloadedMedia?{
        var media = try FilesManager.shared.forUser(signature).getDownloadeMovieById(id)
        return media?.setUser(signature: signature)
    }
    
    static func getEpisodeByID(id : String, season: String, series: String, signature: String)->DownloadedMedia?{
        var media = FilesManager.shared.forUser(signature).getDownloadedEpisode(id: id, season: season, series: series)
        return media?.setUser(signature: signature)
    }
    
        
    
    
    func getObjectAsJSONDictionary() -> [String : Any]? {
          if let data = try? JSONEncoder().encode(self) {
              if var dir = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                  dir.removeValue(forKey: "data")
                  dir["object"] = self.object
                  dir["group"] = self.group?.getObjectAsJSONDictionary()
                  dir["status"] = self.status.rawValue
                  return dir
              }
          }
          return nil
      }
    
}



public struct Season {
    var mediaList : [DownloadedMedia] = []
}


public enum MediaSortKey {
    case name
    case id
    case seasonNumber
    //case episodeNumber
}
public  enum OrderType {
    case asce
    case desc
}

extension [DownloadedMedia] {
    
    public func sortMedia(_ key: MediaSortKey, type : OrderType = .asce)->[DownloadedMedia]{
        return self.sorted { i1, i2 in
            switch(key){
            case .name:
                return  type == .asce ? i1.name > i2.name : i1.name < i2.name
            case .seasonNumber:
                if i1.mediaRetrivalType == .SeasonInfo {
                    if let a = i1.group?.seasonName, let b = i2.group?.seasonName{
                        return  type == .asce ? a > b : a < b
                    }
                }
                break
            default:
                return type == .asce ? i1.mediaId > i2.mediaId : i1.mediaId < i2.mediaId
            }
            return type == .asce ? i1.mediaId > i2.mediaId : i1.mediaId < i2.mediaId
        }
    }    
}


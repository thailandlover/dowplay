//
//  MediaGrouping.swift
//  KeeCustomPlayer
//
//  Created by Ahmed Qazzaz on 05/03/2023.
//

import Foundation


public struct MediaGroup : Codable{
    
    public var showId : String
    public var seasonId : String
    public var episodeId : String
    
    public var seasonName : String
    public var showName : String
    
    private var data : Data?
    mutating func setData(newData: Data?){
        self.data = newData
    }
    
    
    var downloadPath : String {
        return "\(MediaManager.MediaType.series.version_3_value)/\(showId)/\(seasonId)/"
    }
    
    init(showId: String, seasonId: String, episodeId: String,seasonName: String, showName: String,  data: [String:Any]? = nil) {
        self.showId = showId
        self.seasonId = seasonId
        self.episodeId = episodeId
        self.seasonName = seasonName
        self.showName = showName
        self.info = data
    }
    
    public var info : [String:Any]? {
        set{
            if let value = newValue{
                self.data = try? JSONSerialization.data(withJSONObject: value)
            }
        }
        get{
            if let data = data{
                return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any]
            }
            return nil
        }
    }
        
    
    
    public func register(){
        if let data = try? JSONEncoder().encode(self){
            UserDefaults.standard.set(data, forKey: "\(episodeId)_\(MediaManager.MediaType.series.version_3_value)_group")
        }
        
    }
    
    public static func get(usingEpisodeID eid: String)->MediaGroup?{
        if let v = UserDefaults.standard.object(forKey: "\(eid)_\(MediaManager.MediaType.series.version_3_value)_group") as? Data {
            if let obj = try? JSONDecoder().decode(MediaGroup.self, from: v){
                return obj
            }
        }
        
        return nil
    }
    
    func getObjectAsJSONDictionary() -> [String : Any]? {
           if let data = try? JSONEncoder().encode(self) {
               if var dir = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                   dir.removeValue(forKey: "data")
                   dir["info"] = self.info
                   return dir
               }
           }
           return nil
       }
}

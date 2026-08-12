//
//  VideoPlayerViewController.swift
//  KeeCustomPlayer
//
//  Created by Ahmed Qazzaz on 11/11/2022.
//

import UIKit
import AVKit
import MediaPlayer

struct PlayingInfo : Codable{
    var type = MediaManager.MediaType.movie
    var id : String
    var duration : Double
    var currentTime : Double
}


public class VideoPlayerViewController: UIViewController {
    var myReceivedArgs : [String:Any]?
    var myReceivedMediaGroup : [String:Any]?
    var myReceibedInfo : [String:Any]?
    
    public var settings : HostAppSettings = .default
    public static var orientationLock = UIInterfaceOrientationMask.portrait
    public var controllersStayTime : Double = 5
    var routerPickerView :  AVRoutePickerView!
    private var queuePlayer : AVQueuePlayer?
    private var playerLayer : AVPlayerLayer!
    @IBOutlet weak private var playerView : UIView!
    
    private var playingInfoList : [PlayingInfo] = []
    
    private var complete = false
    public var isOpen : Bool {
        return !complete
    }
    private var moveToNextCounter = 5
    private var moveToNextTime : Timer?
    
    @IBOutlet weak private var continueWatchingAlert : UIView!
    @IBOutlet weak private var continueWatchingTitle : UILabel!
    @IBOutlet weak private var continueWatchingAction : UIButton!
    
    private var player : AVQueuePlayer!
    
    // Key-value observing context
    private var playerItemContext = 0
    
    private var playingIndex : Int = 0
    
    private var hasNext : Bool {
        return playingIndex + 1 < mediaQueue.count
    }
    
    private var mediaQueue : [Media] = []
    var media : Media? {
        if mediaQueue.count > 0 { return mediaQueue[playingIndex]}
        return nil
    }
    var localPath : URL?

    private var showingControllerTime : Timer?
    
    private var didInitialized = false
    private var animator : UOAnimator!
        
    @IBOutlet weak private var lb_title : UILabel!
    @IBOutlet weak private var lb_subtitle : UILabel!
    
    @IBOutlet weak private var lb_debugError : UILabel!
    
    @IBOutlet weak private var isLoadingIndicator : UIActivityIndicatorView!
    @IBOutlet weak private var currentTimeLabel : UILabel!
    @IBOutlet weak private var remainingTimeLabel : UILabel!
    @IBOutlet weak internal var seekTimeSlider : UISlider!
    
    @IBOutlet weak private var btn_back : UIButton!
    @IBOutlet weak private var btn_airPlay : UIButton!
    @IBOutlet weak private var btn_cast : UIButton!
    @IBOutlet weak private var btn_resize : UIButton!
    @IBOutlet weak private var btn_download : SSBadgeButton!
    @IBOutlet weak private var btn_pip : UIButton!
    @IBOutlet weak private var btn_settings : UIButton!
    @IBOutlet weak private var btn_playPause : UIButton!
    @IBOutlet weak private var btn_jumpF : UIButton!
    @IBOutlet weak private var btn_jumpB : UIButton!
    @IBOutlet weak private var btn_next : UIButton!
    @IBOutlet weak private var btn_previous : UIButton!
    
    @IBOutlet weak private var vi_infoView : UIView!
    @IBOutlet weak private var vi_controllers : UIView!
    
    @IBOutlet weak private var lb_downloadPercentage : UILabel!
    
    
    private var sliderTouched = false
    /// Where a seek is heading while it is still in flight, nil when the player is in charge.
    private var seekTarget : CMTime?
    
    private var viewsShouldBeHidden : Bool = false
    private var viewsHiddenStatus : Bool = false
    
    private var pipController: AVPictureInPictureController!
    private var pipPossibleObservation: NSKeyValueObservation?
    
    private var settingsController : VideoPlayerSettingsViewController!
    
    @IBOutlet weak private var bottomView : UIView!
    @IBOutlet weak private var topView : UIView!
    
    
    func setPresentationStyle(_ style : UIModalPresentationStyle){
        self.modalPresentationStyle = style
    }


    public override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return .bottom
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        
        AppUtility.lockOrientation(.landscape)
        
        animator = UOAnimator(duration: 1.24, delay: 0.01,animationOptions: .curveEaseOut, damping: 0.85)
        
        continueWatchingAlert.leadingConstraint?.constant = -(continueWatchingAlert.frame.width + 100)
        continueWatchingAlert.layer.cornerRadius = 16
        continueWatchingAlert.isHidden = true
        self.player = AVQueuePlayer()
        playerLayer = AVPlayerLayer(player: player)
        let sH = UIScreen.main.bounds.height
        let sW = UIScreen.main.bounds.width
        playerLayer.frame = CGRect(origin: .zero, size: CGSize(width: sH, height: sW))
        //playerView.bounds
        playerLayer.videoGravity = .resizeAspect
//        playerView.backgroundColor = .red
        
        self.setPlayingItemInfo()
        settingsController = VideoPlayerSettingsViewController(nibName: "VideoPlayerSettingsViewController", bundle: .packageBundle)
                        
        playerView.layer.addSublayer(playerLayer)
        self.view.addSubview(playerView)
        self.view.sendSubviewToBack(playerView)
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                                       , queue: .main,
                                       using: playerDidUpdateTime)
        
        player.addObserver(self,
                           forKeyPath: "rate",
                           context: nil)
        
        setupPipController()
        
        
        settingsController.didChangeSpeedOption = { speed in
            guard self.player != nil, self.player.rate != 0 else {return}
            self.player.rate = Float(speed)
        }
        
        settingsController.didChangeSubTitleOption = { option in
            guard self.player != nil else {return}
            if let group = self.player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                self.player.currentItem?.select(option, in: group)
                
                if let rule = AVTextStyleRule(textMarkupAttributes: [kCMTextMarkupAttribute_BaseFontSizePercentageRelativeToVideoHeight as String: 60]) {
                    self.player.currentItem?.textStyleRules = [rule]
                }
            }
        }
        
        settingsController.didChangeAudioOption = { option in
            guard self.player != nil else {return}
            if let group = self.player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
                self.player.currentItem?.select(option, in: group)
            }
        }
        
        
        //let ll = MPVolumeView(frame: CGRect(origin: .zero, size: CGSize(width: 40,height: 40)))
        
        if let stk = btn_airPlay.superview as? UIStackView {
            routerPickerView =  AVRoutePickerView(frame: CGRect(origin: .zero, size: btn_airPlay.bounds.size))
            if #available(iOS 13.0, *) {
                routerPickerView.largeContentImage = btn_airPlay.currentImage
            } else {
                // Fallback on earlier versions
            }
            
            routerPickerView.activeTintColor = .green
            routerPickerView.tintColor = UIColor.white
            stk.insertArrangedSubview(routerPickerView, at: 0)
            
            
        }
        
        topView.backgroundColor = vi_infoView.backgroundColor
        bottomView.backgroundColor = vi_controllers.backgroundColor
        do {
            try self.validateDownloadButton()
        }catch{
            
        }
    }
    
    
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if UIDevice.current.userInterfaceIdiom == .pad{
            let sH = self.playerView.bounds.height
            let sW = self.playerView.bounds.width
                playerLayer.frame = CGRect(origin: .zero, size: CGSize(width: sH, height: sW))
        }
        
    }
    
   
    
    func setPlayingIndex(_ index : Int){
        playingIndex = index
    }
    
    
    func setPlayingItemInfo(){
        lb_title.text = media?.title
        lb_subtitle.text = media?.subTitle
        lb_subtitle.isHidden = lb_subtitle.text?.isEmpty ?? true
        
        
    }
    
    func validateDownloadButton() throws{        
        btn_download.isHidden = false
        lb_downloadPercentage.isHidden = true
        if let id = media?.keeId, let type = media?.type{
            var isDownloaded = false
            if type == .movie {
                isDownloaded = try DownloadedMedia.getMovieByID(id: id,signature: settings.userSignature) != nil
                localPath = try? FilesManager.shared.getFileForMovie(mediaID: id)
            }else{
                if let g = self.media?.mediaGroup {
                    isDownloaded = (DownloadedMedia.getEpisodeByID(id: g.episodeId, season: g.seasonId, series: g.showId, signature: settings.userSignature) != nil)
                    localPath = try? FilesManager.shared.getFileForEpisode(id: g.episodeId, season: g.seasonId, series: g.showId)
                }
            }
                        
            if  isDownloaded {
                btn_download.tintColor = .systemGreen
                btn_download.tag = 2
            }else if DownloadManager.shared.isDownloadingMediaWithID(id, ofType: type) {
                btn_download.tintColor = .systemOrange
                if DownloadManager.shared.isDownloadingMediaWithIDSuspended(id, ofType: type){
                    btn_download.tag = -1
//                    btn_download.alpha = 0.5
                    btn_download.tintColor = .red
                    if let progress = DownloadManager.shared.getDownloadProgress(ForMediaId: id, ofMediaType: type) {
                        
                        DispatchQueue.main.async {
                            self.lb_downloadPercentage.text = String(format: "%02.2f%%", progress * 100)
                        }
                    }
                    
                }else{
                    btn_download.tag = 1
                }
                lb_downloadPercentage.isHidden = false
                NotificationCenter.default.addObserver(self, selector: #selector(downloadProgressReceiver(notification:)), name: NSNotification.Name(rawValue: "downloadTask_media_\(id)_\(type.version_3_value)_\(settings.userSignature)"), object: nil)
            }else{
                btn_download.tag = 0
                btn_download.tintColor = .white
            }
        }else{
            btn_download.tag = 0
            btn_download.tintColor = .white
        }
        
        if media?.downloadURL == nil {
            btn_download.isHidden = true
        }
    }
    
    @objc func downloadProgressReceiver( notification : Notification) {
        if let downloadTask = notification.object as? URLSessionDownloadTask {
            if let id = media?.keeId, let type = media?.type {
                if let taskID = downloadTask.mediaId{
                    let ID = "\(taskID)"
                    if ID == "\(id)_\(type.version_3_value)_\(settings.userSignature)" {
                        DispatchQueue.main.async {
                            self.lb_downloadPercentage.text = String(format: "%02.2f%%", downloadTask.progress.fractionCompleted * 100)
                        }
                        
                    }
                }
            }
        }
    }
    
    
    
    func initSubtitleStyle(forItem item: AVPlayerItem?) {
        let textStyle:AVTextStyleRule = AVTextStyleRule(textMarkupAttributes: [
            kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String: [0.2,0.3,0.0,0.3]
            ])!


        let textStyle1:AVTextStyleRule = AVTextStyleRule(textMarkupAttributes: [
            kCMTextMarkupAttribute_ForegroundColorARGB as String: [0.2,0.8,0.4,0.0]
            ])!

        let textStyle2:AVTextStyleRule = AVTextStyleRule(textMarkupAttributes: [
            kCMTextMarkupAttribute_BaseFontSizePercentageRelativeToVideoHeight as String: 120,
            kCMTextMarkupAttribute_CharacterEdgeStyle as String: kCMTextMarkupCharacterEdgeStyle_None
            ])!

        item?.textStyleRules = [textStyle, textStyle1, textStyle2]
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        self.checkNextPreviousButtonStatsu()
        
                               
//        let isCastConnected = GCKCastContext.sharedInstance().sessionManager.hasConnectedSession()
//        if isCastConnected {
//            if((GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.mediaStatus) != nil){
////                if let nvc = self.navigationController {
////
////                    nvc.popViewController(animated: true)
////                }else{
////                    self.dismiss(animated: true) {
//                        self.startCastingVideo()
////                    }
////                }
//            }
//
//
//        }
        
    }
    

    
    private func setupPipController(){
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
                // Create a new controller, passing the reference to the AVPlayerLayer.
                pipController = AVPictureInPictureController(playerLayer: playerLayer)
                pipController.delegate = self

                pipPossibleObservation = pipController.observe(\AVPictureInPictureController.isPictureInPicturePossible,
        options: [.initial, .new]) { [weak self] _, change in
                    // Update the PiP button's enabled state.
                    //self?.pipButton.isEnabled = change.newValue ?? false
                    self?.btn_pip.isHidden = false
                }
            } else {
                // PiP isn't supported by the current device. Disable the PiP button.
                //pipButton.isEnabled = false
                btn_pip.isHidden = true
            }
    }

    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        setPlayingItem()
    }
    
    func checkNextPreviousButtonStatsu(){
            self.btn_next.isHidden = mediaQueue.count < 2
            self.btn_previous.isHidden = mediaQueue.count < 2
        guard mediaQueue.count >= 2 else {return}
        self.btn_previous.isEnabled = playingIndex > 0
        self.btn_next.isEnabled = (playingIndex + 1) < mediaQueue.count
    }
    
    func setPlayingItem(){
        let playURL = localPath ?? URL(string: media?.urlToPlay ?? "")
        if let url = playURL, !(didInitialized){
            //stop current playing item
            player.pause()
            player.replaceCurrentItem(with: nil)
            // Whatever a seek on the previous item was waiting for does not apply to this one.
            seekTarget = nil
            // load new item
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = TimeInterval(5)
            item.addObserver(self,
                             forKeyPath: #keyPath(AVPlayerItem.status),
                             options:  [.old, .new],
                             context: &playerItemContext)
            
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp), options:  [.old, .new],
                             context: &playerItemContext)
            
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp), options:  [.old, .new],
                             context: &playerItemContext)
            
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferEmpty), options:  [.old, .new],
                             context: &playerItemContext)
            
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferFull), options:  [.old, .new],
                             context: &playerItemContext)
                        

            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying(note:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item)
                //.addObserver(self, selector: "playerDidFinishPlaying:", name: AVPlayerItemDidPlayToEndTimeNotification, object: item)
            self.initSubtitleStyle(forItem: item)
            player.replaceCurrentItem(with: item)
            player.automaticallyWaitsToMinimizeStalling = item.isPlaybackBufferEmpty
            didInitialized = true
            moveToNextTime?.invalidate()
            moveToNextTime = nil
            isLoadingIndicator.startAnimating()
            checkNextPreviousButtonStatsu()
        }
        
        if media == nil {
            isLoadingIndicator.stopAnimating()
            self.lb_debugError.text = "Debug\n No media object or media list was provided"
        }
    }
    
    
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.setPlayingInfoForCurrentMedia()
        AppUtility.lockOrientation(.portrait)
        if localPath == nil {
            self.updateWatchTime()
        }
        self.player.pause()
        self.player = nil
        self.complete = true
    }
    
    private func updateWatchTime(){
        if let media = media {
            NetworkOperatinosManager.default.updateWatchTime(forMedia: media,settings: settings, updateTime: player.currentTime().seconds, mediaDuration: player.currentItem?.duration.seconds ?? 0)
        }
    }
    
    
    @IBAction func playPauseAction(_ sender : UIButton?) {
        if self.player.rate == 0 {
            self.player.play()
            self.btn_playPause.setImage(UIImage(named: "ic_player_pause", in: .packageBundle,compatibleWith: .none), for: .normal)
        }else{
            self.player.pause()
            self.btn_playPause.setImage(UIImage(named: "ic_player_play", in: .packageBundle,compatibleWith: .none), for: .normal)
        }
    }
    
    @IBAction func jumpForwardAction(_ sender : UIButton?) {
        let currentTime = self.player.currentTime().seconds
        //let change : Int64 = 10000000000//Int64(10 * currentTime.timescale)
        let newSecondes = currentTime + 10//CMTimeValue(currentTime.value + change)
        //self.player.seek(to: CMTime(value: CMTimeValue(newSecondes), timescale: currentTime.timescale))
        self.seekToSeconds(value: newSecondes)
        setTimerToHideControllers()
    }
    
    @IBAction func jumpBackwardAction(_ sender : UIButton?) {
        let currentTime = self.player.currentTime().seconds
//        let change : Int64 = 10000000000
        let newSecondes = currentTime - 10 //CMTimeValue(currentTime.value - change)
//        self.player.seek(to: CMTime(value: CMTimeValue(newSecondes), timescale: currentTime.timescale))
        self.seekToSeconds(value: newSecondes)
        setTimerToHideControllers()
    }
    
    @IBAction func nextAction(_ sender : UIButton?) {
//        let nextItem = player.items()[playingIndex + 1]
        
        self.setPlayingInfoForCurrentMedia()
        player.pause()
        localPath = nil
        self.updateWatchTime()
        playingIndex += 1
        didInitialized = false
        self.setPlayingItemInfo()
        setPlayingItem()
        try? self.validateDownloadButton()
        setTimerToHideControllers()
    }
    
    @IBAction func previousAction(_ sender : UIButton?) {
        self.setPlayingInfoForCurrentMedia()
        player.pause()
        localPath = nil
        self.updateWatchTime()
        playingIndex -= 1
        didInitialized = false
        self.setPlayingItemInfo()
        setPlayingItem()
        try? self.validateDownloadButton()
        setTimerToHideControllers()
    }
    
    func setPlayingInfoForCurrentMedia(){
        if let duration = player.currentItem?.duration,
           let currentTime = player.currentItem?.currentTime(),
           let id = media?.keeId{
            
            let pi = PlayingInfo(type:media?.type ?? .movie,
                                 id: id,
                                 duration: duration.seconds,
                                 currentTime: currentTime.seconds)
            
            if let index = playingInfoList.firstIndex(where: {$0.id == id}){
                playingInfoList[index] = pi
            }else{
                playingInfoList.append(pi)
            }
        }
    }
    
    public func getPlayingInfo()->[[String:Any]]{
        if let data = try? JSONEncoder().encode(playingInfoList) {
            if let result = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [[String:Any]] {
                return result
            }
        }
        
        return []
    }
        
//    @IBAction func seekAction(_ sender : UISlider, event : UIEvent) {

//    }
    
    @IBAction func sliderDown(_ sender : Any?) {
        sliderTouched = true
    }
    
    
    @IBAction func seekActionUpIn(_ sender: UISlider, forEvent event: UIEvent) {
        self.seekAction(sender, forEvent: .touchUpInside)
    }
    
    @IBAction func seekActionUpOut(_ sender: UISlider, forEvent event: UIEvent) {
        self.seekAction(sender, forEvent: .touchUpOutside)
    }
    
    func seekAction(_ sender: UISlider, forEvent event: UIControl.Event) {
        if event == UIControl.Event.touchUpOutside {
            if sliderTouched == false {
                return
            }
        }
        self.seekTo(value: Double(sender.value))
        sliderTouched = false
    }
    
    private func seekTo(value : Double){
        guard let item = self.player.currentItem else {return}
        let newValue = item.duration.seconds * value

        let time = CMTime(seconds: newValue, preferredTimescale: item.duration.timescale)
        self.seek(to: time)
    }

    /// Moves the player and keeps the slider and the labels on the position the user asked for
    /// until the player actually reaches it.
    ///
    /// Handing them straight back to the periodic time observer used to make them jump: while the
    /// seek is buffering, `currentItem.currentTime()` still reports the position the player is
    /// leaving, so the thumb snapped back there and only reached the requested point once the data
    /// had arrived.
    private func seek(to time: CMTime) {
        guard self.player != nil else {return}
        self.seekTarget = time
        self.showTime(time)
        self.player.seek(to: time) { [weak self] finished in
            // An unfinished seek means a newer one replaced it, and that one owns the UI now.
            guard finished else {return}
            DispatchQueue.main.async {
                self?.seekTarget = nil
            }
        }
    }

    /// Paints the slider and the two labels for a given position.
    private func showTime(_ time: CMTime) {
        guard let item = self.player?.currentItem else {return}
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0, time.seconds.isFinite else {return}

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad

        self.remainingTimeLabel.text = formatter.string(from: TimeInterval(duration - time.seconds))
        self.currentTimeLabel.text = formatter.string(from: TimeInterval(time.seconds))
        self.seekTimeSlider.value = Float(time.seconds / duration)
    }
    
    @IBAction func backAction(_ sender : UIButton) {
        if let nvc = self.navigationController {
            nvc.popViewController(animated: true)
        }else{
            self.dismiss(animated: true)
        }
            
    }
    
    private func seekToSeconds(value : Double){
        guard let item = self.player.currentItem else {return}

        let time = CMTime(seconds: value, preferredTimescale: item.duration.timescale)
        self.seek(to: time)
    }
    
   
    
    @IBAction func castAction(_ sender : UIButton) {
//        GCKCastContext.sharedInstance().presentCastDialog()
//        GCKCastContext.sharedInstance().
    }
    
    @IBAction func airPlayAction(_ sender : UIButton) {
        
    }
    
    @IBAction func continueFromWatchingTime(_ sender : Any?) {
        if continueWatchingAction.tag == 0 {
            if let value = media?.currentWatchTime {
                seekToSeconds(value: value)
            }
        }else if continueWatchingAction.tag == 1{ //move to next episode
            self.nextAction(nil)
        }
        hideContinueFromWatchingTime()
    }
    
    @IBAction func cancelContinueFromWatchingTime(_ sender : Any?) {
        hideContinueFromWatchingTime()
    }
    
    private func showContinueFromWatchingTime(){
        continueWatchingAction.setTitle("Continue", for: .normal)
        continueWatchingAction.tag = 0
        continueWatchingTitle.text = "Continue from where you stopped"
        animator.animateTo(forView: continueWatchingAlert, leadingConstant: 12)
        continueWatchingAlert.isHidden = false
        
    }
    
    private func hideContinueFromWatchingTime(){
        animator.animateTo(forView: continueWatchingAlert, leadingConstant: -(continueWatchingAlert.frame.width + 100)) {
            self.continueWatchingAlert.isHidden = true
        }
    }
    
    
    private func showMoveToNextEpisode(){
        moveToNextCounter = 10
        continueWatchingAction.setTitle("Next (\(moveToNextCounter))", for: .normal)
        continueWatchingAction.tag = 1
        continueWatchingTitle.text = "Start next episode"
        animator.animateTo(forView: continueWatchingAlert, leadingConstant: 12)
        continueWatchingAlert.isHidden = false
        
        moveToNextTime = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { t in
            if (self.moveToNextCounter == 0){
                t.invalidate()
                self.hideMoveToNextEpisode()
            }else{
                self.moveToNextCounter -= 1
                self.continueWatchingAction.setTitle("Next (\(self.moveToNextCounter))", for: .normal)
            }
        })
    }
    
    private func hideMoveToNextEpisode(){
        animator.animateTo(forView: continueWatchingAlert, leadingConstant: -(continueWatchingAlert.frame.width + 100)) {
            self.continueWatchingAlert.isHidden = true
        }
    }
        
    @IBAction func resizeAction(_ sender : UIButton) {
        playerLayer.videoGravity = playerLayer.videoGravity == .resizeAspect ? .resizeAspectFill : .resizeAspect
        //playerLayer.videoGravity = .resizeAspect
    }
    
    @IBAction func pipAction(_ sender : UIButton) {
        if pipController.isPictureInPictureActive {
               pipController.stopPictureInPicture()
           } else {
               pipController.startPictureInPicture()
           }
    }
    
    var blinkStatus:Bool = false
    @IBAction func downloadAction(_ sender : UIButton) {
        if btn_download.tag == 0 {
            //        DownloadManager.shared.download(link: media?.urlToPlay ?? "")
            if let url = URL(string: media?.downloadURL ?? "") {
                if(media?.type == .series){
                    let mediaGroup : MediaGroup = MediaGroup(showId: media?.mediaGroup?.showId as! String, seasonId: media?.mediaGroup?.seasonId as! String, episodeId: media?.keeId as! String,seasonName: media?.mediaGroup?.seasonName as! String,showName: media?.mediaGroup?.showName as! String ,data: self.myReceivedMediaGroup)
                    DownloadManager.shared.startDownload(url: url, forMediaId: Int(media?.keeId ?? "") ?? -1,mediaName: media?.title ?? "Untitled", type: .series,mediaGroup: mediaGroup, object:self.myReceivedArgs)
                } else {
                    DownloadManager.shared.startDownload(url: url,
                                                         forMediaId: Int(media?.keeId ?? "") ?? -1 ,
                                                         mediaName: media?.title ?? "Untitled",
                                                         type: media?.type ?? .movie,
                                                         mediaGroup: media?.mediaGroup,
                                                         object: media?.info)
                }
                
                try? validateDownloadButton()
            }
        }else if btn_download.tag == 1 {
            //should Pause
            
//            UIView.animate(withDuration: 0.24, delay: 0, options:.repeat , animations: {
//                self.btn_download.alpha = self.blinkStatus ? 0 : 1
//            }) { done in
//                self.blinkStatus = !self.blinkStatus
//            };
            //btn_download.alpha = 0.5
            btn_download.tintColor = .red
            btn_download.tag = -1
            DownloadManager.shared.pauseDownload(forMediaId: media?.keeId ?? "", ofType: media?.type ?? .movie)
                
        }else if btn_download.tag == -1{
            btn_download.tag = 1
            btn_download.tintColor = .orange
            DownloadManager.shared.resumeDownload(forMediaId: media?.keeId ?? "", ofType: media?.type ?? .movie)
        }
    }
    
    @IBAction func settingsAction(_ sender : UIButton) {
        self.settingsController.show(inView: self.view)
    }
    
    public override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard self.player != nil else {return}
                        
        if keyPath == "rate"{
            if player.rate == 0 {
                self.showViews()
            }else{
                if viewsShouldBeHidden {
                    self.setTimerToHideControllers()
                    // self.hideViews()
                }
            }
            return
        }
        
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
            return
        }
        
        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }

            isLoadingIndicator.stopAnimating()
            // Switch over status value
            switch status {
            case .readyToPlay:
                // Player item is ready to play.
                self.viewsShouldBeHidden = true
                self.updateItemInfo(self.player.currentItem!)
                self.play()
                self.enableAll()
                self.hideViews()
                
                if let group = self.player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible), let f = group.options.first {
                    self.player.currentItem?.select(f, in: group)
                }
                
//                if (media?.currentWatchTime ?? 0) > 0 {
//                    self.showContinueFromWatchingTime()
//                }
                
                
                let sH = self.playerView.bounds.height
                let sW = self.playerView.bounds.width
                
//                if UIDevice.current.userInterfaceIdiom == .pad{
                    playerLayer.frame = CGRect(origin: .zero, size: CGSize(width: sW, height: sH))
//                }else{
//                    playerLayer.frame = CGRect(origin: .zero, size: CGSize(width: sH, height: sW))
//                }
                
                
                
                
                break
            case .failed:
                // Player item failed. See error.
                print("failed to load")
                if localPath != nil {
                    do{
                        try self.validateDownloadButton()
                    }catch{
                        print(error)
                    }
                }
                break
            case .unknown:
                // Player item is not yet ready.
                print("Unknown status (loading)")
                break
            @unknown default:
                //error
                print("ERROR")
                break
            }
        }
        
        if keyPath == #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp) ||
            keyPath == #keyPath(AVPlayerItem.isPlaybackBufferFull){
            self.updateBufferTimeInterval()
        }

    }
        
    private func updateBufferTimeInterval(){
        var isPlaying: Bool {
            if (self.player.rate != 0 && self.player.error == nil) {
                return true
            } else {
                return false
            }
        }
        if(isPlaying){
            self.player.currentItem?.preferredForwardBufferDuration = TimeInterval(5)
            self.player.automaticallyWaitsToMinimizeStalling = player.currentItem?.isPlaybackBufferEmpty ?? false
            self.player.play()
        }
    }
    
    
    func enableAll(){
        seekTimeSlider.isEnabled = true
        btn_resize.isEnabled = true
        btn_cast.isEnabled = true
//        btn_airPlay.isEnabled = true
        btn_pip.isEnabled = true
        btn_download.isEnabled = true
        btn_settings.isEnabled = true
        btn_playPause.isEnabled = true
        btn_jumpB.isEnabled = true
        btn_jumpF.isEnabled = true
        checkNextPreviousButtonStatsu()
    }
        
    private func play(){
        self.player.play()
        if let value = media?.startAt, value > 0 {
            seekToSeconds(value: Double(value))
        }
            self.btn_playPause.setImage(UIImage(named: "ic_player_pause", in: .packageBundle,compatibleWith: .none), for: .normal)
    }
    
    private func pause(){
        self.player.pause()
        self.btn_playPause.setImage(UIImage(named: "ic_player_play", in: .packageBundle,compatibleWith: .none), for: .normal)
    }
    
    private func hideViews(){
         func hideInfoView(){
            if vi_infoView.topConstraint?.constant == 0 { // still visible
                animator.animateTo(forView: vi_infoView, topConstant: -(vi_infoView.frame.height + 8))
            }
        }
        
         func hideControllerView(){
            if vi_controllers.bottomConstraint?.constant == 0 { // still visible
                animator.animateTo(forView: vi_controllers, bottomConstant: -(UIScreen.main.bounds.height))
//                animator.animateTo(forView: vi_controllers, bottomConstant: -(vi_controllers.frame.height + (UIScreen.main.bounds.height - vi_controllers.frame.origin.y)))
            }
        }
        
        hideControllerView()
        hideInfoView()
        self.viewsHiddenStatus = true
        
        
    }
    
    private func showViews(){
         func showInfoView(){
            if (vi_infoView.topConstraint?.constant ?? 0) < 0 { // still visible
                animator.animateTo(forView: vi_infoView, topConstant: 0)
            }
        }
        
        
        
         func showControllerView(){
            if (vi_controllers.bottomConstraint?.constant ?? 0) < 0 { // still visible
                animator.animateTo(forView: vi_controllers, bottomConstant: 0)
            }
        }
        
        showInfoView()
        showControllerView()
        self.viewsHiddenStatus = false
    }
    
    
    
    
    func updateItemInfo(_ item : AVPlayerItem){
        let formatter = DateComponentsFormatter()
                        formatter.allowedUnits = [.hour, .minute, .second]
                        formatter.unitsStyle = .positional
                        formatter.zeroFormattingBehavior = .pad
        let remainningTime = item.duration.seconds - item.currentTime().seconds
        guard !remainningTime.isNaN else {return}

        // The player arrived where it was sent, so it owns the UI again even if the completion
        // handler of the seek never came back.
        if let target = self.seekTarget, abs(item.currentTime().seconds - target.seconds) < 1 {
            self.seekTarget = nil
        }

        if self.sliderTouched == false && self.seekTarget == nil {
            self.showTime(item.currentTime())
        }
        
        if remainningTime < 7 && moveToNextTime == nil && hasNext{
            self.showMoveToNextEpisode()
        }
        
        
        
        if #available(iOS 15.0, *) {
            player.currentItem?.asset.loadMediaSelectionGroup(for: .audible, completionHandler: { group, error in
                if let group = group {
                    self.settingsController.audioGroupList = group
                }
            })
            player.currentItem?.asset.loadMediaSelectionGroup(for: .legible, completionHandler: { group, error in
                if let group = group {
                    self.settingsController.subTitlesGroupList = group
                }
            })
        } else {
            // Fallback on earlier versions
            self.settingsController.audioGroupList = player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
            
            self.settingsController.subTitlesGroupList = player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        }
        
    }
    
    func playerDidUpdateTime(time : CMTime){
        guard player != nil else {return}        
        if let item = player.currentItem{
            self.updateItemInfo(item)
        }
    }
    
      
    @IBAction func topOnPlayer(_ sender: UITapGestureRecognizer) {
        if (vi_infoView.topConstraint?.constant ?? 0) >= 0 {
            self.hideViews()
        }else{
            self.showViews()
            setTimerToHideControllers()
        }
    }
    
    private func setTimerToHideControllers(){
        if showingControllerTime != nil {showingControllerTime?.invalidate()}
        
        showingControllerTime = Timer.scheduledTimer(withTimeInterval: controllersStayTime,
                             repeats: false) { t in
            if let player = self.player {
                if player.rate > 0 {
                    if self.sliderTouched {
                        self.setTimerToHideControllers()
                    }else{
                        self.hideViews()
                    }
                }
            }
        }
    }
    
    public override var shouldAutorotate: Bool {
        return false
    }
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    
    @objc func playerDidFinishPlaying(note: NSNotification) {
        // Your code here
 
    }
    
//    func startCastingVideo(){
//
//        if let title : String = media?.title,
//           let description : String = media?.subTitle,
//           let posterPhoto : String = media?.subTitle,
//           let mediaUrl : String = media?.urlToPlay
//        {
//            let playPosition : Double = 0
//            let tMetadata:GCKMediaMetadata = GCKMediaMetadata(metadataType: GCKMediaMetadataType.movie)
//            tMetadata.setString(title, forKey: kGCKMetadataKeyTitle)
//            tMetadata.setString(description,
//                                forKey: kGCKMetadataKeySubtitle)
//            if let url = URL(string: posterPhoto) {
//                tMetadata.addImage(GCKImage(url: url,
//                                            width: 480,
//                                            height: 360))
//            }
//            
//            
//            let url = URL.init(string: mediaUrl)
//            guard let mediaURL = url else {
//                print("invalid mediaURL")
//                return
//            }
//            let mediaInfoBuilder = GCKMediaInformationBuilder.init(contentURL: mediaURL)
//            mediaInfoBuilder.streamType = GCKMediaStreamType.buffered;
//            mediaInfoBuilder.contentType = "video/mp4"
//            mediaInfoBuilder.metadata = tMetadata;
//            
//            let tMediaInfo = mediaInfoBuilder.build()
//            let tMediaLoadOption = GCKMediaLoadOptions()
//            tMediaLoadOption.autoplay = true;
//            let playedPos : TimeInterval = playPosition
//            tMediaLoadOption.playPosition = playedPos;
//            
//            let sessionManager = GCKCastContext.sharedInstance().sessionManager
//            if let request = sessionManager.currentSession?.remoteMediaClient?.loadMedia(tMediaInfo,with:tMediaLoadOption) {
//                request.delegate = self
//            }
//            GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
//        }
//        
//    }
    
//    func requestDidComplete(_ request: GCKRequest) {
//        print(request)
//    }
//
//    func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) {
//        print(abortReason)
//    }
//
//    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
//        print(error)
//    }
    
}

extension VideoPlayerViewController : AVPictureInPictureControllerDelegate {
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // Restore the user interface.
        completionHandler(true)
    }
    
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Hide the playback controls.
        // Show the placeholder artwork.
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Hide the placeholder artwork.
        // Show the playback controls.
    }
}


//Public Functions
extension VideoPlayerViewController {
    
    func setSettings(_ settings : HostAppSettings){
        self.settings = settings
    }
    
    func setMediaList(mediaList: [Media], startingIndex : Int = 0, playOnStart : Bool = true){
        self.mediaQueue = mediaList
        self.playingIndex = startingIndex
//        self.setPlayingItem()
    }
    
    public func getPlayingMediaInfo()->[String:Any?]{
        var playingMediaInfo : [String : Any?] = [:]
        playingMediaInfo[.KVP_currentItem] = media
        playingMediaInfo[.KVP_playingIndex] = playingIndex
        playingMediaInfo[.KVP_currentTime] = player?.currentItem?.currentTime().seconds
        playingMediaInfo[.KVP_duration] = player?.currentItem?.duration.seconds
        playingMediaInfo[.KVP_isPlaying] = (player?.rate ?? 0) > 0
        playingMediaInfo[.KVP_playbackSpeed] = player?.rate ?? 0
 
        return playingMediaInfo
    }
    
    func playerShouldPerform(action : PlayerAction, userInfo : [String:Any]?) {
        switch action {
                   
        case .playAction:
            self.play()
        case .pauseAction:
            self.pause()
        case .nextAction:
            self.nextAction(nil)
        case .previousAction:
            self.previousAction(nil)
        case .jumpFAction:
            self.jumpForwardAction(nil)
        case .jumpBAction:
            self.jumpBackwardAction(nil)
        case .seekToTime:
            if let seekValue = userInfo?[.KVP_seekToValue] as? Double {
                self.seekTo(value: seekValue)
            }
        }
    }
}

enum PlayerAction : String {
    case playAction = "Play"
    case pauseAction = "pause"
    case nextAction = "Next"
    case previousAction = "Previous"
    case jumpFAction = "Jump Forward"
    case jumpBAction = "Jump Backward"
    case seekToTime = "Seek To"
}

extension String{
    static var KVP_currentItem = "currentItem"
    static var KVP_playingIndex = "playingIndex"
    static var KVP_currentTime = "currentTime"
    static var KVP_duration = "mediaDuration"
    static var KVP_isPlaying = "isPlaying"
    static var KVP_playbackSpeed = "playbackSpeed"
    
    static var KVP_seekToValue = "seekingValue"
}



public enum DonwloadManagerError : Error {
    case managerIsNotConfiged
    
    var message : String {
        switch self {
        case .managerIsNotConfiged:
            return "Manager is not confied please call DownloadManager.shared.config() function before using any query function from the download manager class"
        }
    }
}

class DebugLabel : UILabel {
    override var text: String?{
        didSet{
            self.isHidden = (text ?? "").isEmpty
        }
    }
}





extension UIViewController {
    
    func setDeviceOrientation(orientation: UIInterfaceOrientationMask) {
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        } else {
            UIDevice.current.setValue(orientation.toUIInterfaceOrientation.rawValue, forKey: "orientation")
        }
    }
}

extension UIInterfaceOrientationMask {
    var toUIInterfaceOrientation: UIInterfaceOrientation {
        switch self {
        case .portrait:
            return UIInterfaceOrientation.portrait
        case .portraitUpsideDown:
            return UIInterfaceOrientation.portraitUpsideDown
        case .landscapeRight:
            return UIInterfaceOrientation.landscapeRight
        case .landscapeLeft:
            return UIInterfaceOrientation.landscapeLeft
        default:
            return UIInterfaceOrientation.unknown
        }
    }
}

@available(iOS 13.0, *)
final class DeviceOrientation {
    
    static let shared: DeviceOrientation = DeviceOrientation()
    
    // MARK: - Private methods
    
    
    private var windowScene: UIWindowScene? {
        return UIApplication.shared.connectedScenes.first as? UIWindowScene
    }
    
    // MARK: - Public methods
    
    func set(orientation: UIInterfaceOrientationMask) {
        if #available(iOS 16.0, *) {
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        } else {
            UIDevice.current.setValue(orientation.toUIInterfaceOrientation.rawValue, forKey: "orientation")
        }
    }
    
    var isLandscape: Bool {
        if #available(iOS 16.0, *) {
            return windowScene?.interfaceOrientation.isLandscape ?? false
        }
        return UIDevice.current.orientation.isLandscape
    }
    
    var isPortraint: Bool {
        if #available(iOS 16.0, *) {
            return windowScene?.interfaceOrientation.isPortrait ?? false
        }
        return UIDevice.current.orientation.isPortrait
    }
    
    var isFlap: Bool {
        if #available(iOS 16.0, *) {
            return false
        }
        return UIDevice.current.orientation.isFlat
    }
}

class UserObject : Codable{
     var isMale : Int?
     var name : String?
     var age : Int?
    func store(key: String){
        if let data = try? JSONEncoder().encode(self){
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    static func reStore(key: String) -> UserObject?{
        if let data = UserDefaults.standard.object(forKey: key) as? Data{
            return try? JSONDecoder().decode(UserObject.self, from: data)
        }
        return nil
    }
}




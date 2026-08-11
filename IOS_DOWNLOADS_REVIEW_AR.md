<div dir="rtl" align="right">

# مراجعة تعديلات التحميلات على iOS — ملف ملف، بلوك بلوك

هذا الملف مكتوب عشان تقدر تراجع كل سطر اتغيّر وتفهم ليش، وتتأكد بنفسك إن ريسبونس المكتبة ما تغيّر.

- كل الشرح بالعربي من اليمين لليسار، وكل بلوكات الكود بالإنجليزي من اليسار لليمين.
- «قبل» = كود الكوميت `3577bfb` (اللي كان شغال على المستخدمين).
- «بعد» = الكود الحالي بعد الإصلاح.
- كل بلوك فيه سطر **أثر على الريسبونس** حتى تعرف مباشرة إذا في شي بيوصل لتطبيق الموبايل مختلف.

</div>

---

<div dir="rtl" align="right">

## 0. الدليل العملي: هل تغيّر شكل الريسبونس؟

قبل أي شرح، هذا قياس فعلي مش كلام. كتبت اختبار اسمه `ResponseShapeSnapshotTests` بيطبع شكل كل ريسبونس بترجعه المكتبة لفلاتر (المفاتيح + نوع كل قيمة + القيم اللي التطبيق بيفرّع عليها). الاختبار مكتوب بحيث يشتغل على **النسخة القديمة والجديدة**، وشغّلته على ثلاث نسخ من نفس المكتبة:

| النسخة | شو هي |
| --- | --- |
| `83d2446` | ما قبل الكوميت الخاطئ |
| `3577bfb` | النسخة اللي على المستخدمين حالياً |
| الحالية | بعد الإصلاح |

النتيجة على 9 ريسبونسات (فيلم جاري / موقوف / مستأنف / مكتمل، مسلسل، مواسم، حلقات، `get_download_movie` بحالتين):

**مجموعات المفاتيح متطابقة 100% في النسخ الثلاث** — ولا مفتاح انضاف ولا مفتاح انحذف. هذا ناتج المقارنة الآلية:

</div>

```text
=== key sets identical across the three builds? ===
YES - identical key sets in all 9 payloads across all three builds
```

<div dir="rtl" align="right">

الفرق الوحيد كان في **قيمة** `progress` (مش في شكلها ولا نوعها):

| الريسبونس | ما قبل الكوميت الخاطئ | `3577bfb` (الحالي عند المستخدمين) | بعد الإصلاح |
| --- | --- | --- | --- |
| `get_downloads_list` / فيلم جاري | 0 | 0 | 0.2875 |
| `get_downloads_list` / فيلم موقوف | 0 | 0 | 0.2875 |
| `get_downloads_list` / فيلم مستأنف | 0.88125 | **0** | 0.8515625 |
| `season_episodes_downloads_list` | 0 | 0 | 0.2875 |

يعني النسخة اللي على المستخدمين الآن بترجّع `progress = 0` طول الوقت للتحميلات الجارية (لأن الفورجراوند سيشن ما كان بيرفع تقدّم المهمة)، والإصلاح رجّع التقدّم الحقيقي. هذا **تحسين في القيمة، مش تغيير في العقد** — نفس المفتاح، نفس النوع (رقم بين 0 و 1).

شكل العناصر الجارية بالضبط في النسخ الثلاث:

</div>

```text
get_downloads_list/movie.running ->
  [mediaId:String, mediaRetrivalType:String, mediaType:String, name:String,
   object:Map, progress:Number, status:Int]

season_episodes_downloads_list/row ->
  [group:Map, mediaId:String, mediaRetrivalType:String, mediaType:String, name:String,
   object:Map, progress:Number, status:Int]

get_downloads_list/movie.completed ->
  [mediaId:String, mediaRetrivalType:String, mediaType:String, name:String,
   object:Map, progress:Number, status:Int, tempPath:String]
```

<div dir="rtl" align="right">

وتقدر تكرّر القياس بنفسك بأي لحظة:

</div>

```sh
cd example/ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'id=<simulator-udid>' \
  -only-testing:RunnerTests/ResponseShapeSnapshotTests | grep '^SHAPE|'
```

---

<div dir="rtl" align="right">

# الملف الأول: `ios/Classes/Managers/DownloadManager.swift`

هذا الملف اللي فيه كل الشغل. 12 بلوك، كل واحد لحاله تحت.

## 1-1. جلسة التحميل (`init`)

</div>

**قبل**

```swift
private var urlSession: URLSession!
private var foregroundUrlSession: URLSession!

override private init() {
    super.init()
    let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).background")
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.allowsCellularAccess = true
    urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

    // Foreground session: used for active downloads while the app is open
    let foregroundConfig = URLSessionConfiguration.default
    foregroundConfig.allowsCellularAccess = true
    foregroundUrlSession = URLSession(configuration: foregroundConfig, delegate: self, delegateQueue: nil)

    updateTasks()
}
```

**بعد**

```swift
private var urlSession: URLSession!

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
```

<div dir="rtl" align="right">

**ليش:** جلسة `.default` بتموت مع التطبيق. لما التطبيق يروح للخلفية بتتجمد بعد ~30 ثانية، ولو النظام قتل التطبيق بتنعدم مهامها ولا في طريقة تعدادها بعد الإقلاع. الجلسة الخلفية (`background`) هي الوحيدة اللي بتكمل والتطبيق مسكّر، وبترجع مهامها لما التطبيق يشتغل من جديد.

**السيناريو:** مستخدم يبلّش تحميل → يقفل الشاشة أو يفتح تطبيق ثاني → بعد 30 ثانية iOS بيعلّق التطبيق → التحميل بيوقف؛ ولو النظام أنهى التطبيق، المهمة راحت بلا رجعة والليست بتصير فاضية.

**أثر على الريسبونس:** لا يوجد تغيير في الشكل. الأثر الوحيد إن `progress` رجع يعطي قيمته الحقيقية (شوف القسم 0)، والتحميل صار يكمل بالخلفية.

**ملاحظة:** الإعدادات اللي أجت مع الكوميت الخاطئ لحل البطء (`isDiscretionary = false` و `allowsCellularAccess = true` وحذف `countOfBytesClientExpectsToReceive`) **محفوظة كما هي** — الغلط كان بتبديل نوع الجلسة فقط.

## 1-2. توقيع المستخدم (`userSignature`)

</div>

**قبل**

```swift
var userSignature : String {
    return settings.userSignature      // settings is HostAppSettings! (implicitly unwrapped)
}
```

**بعد**

```swift
var userSignature : String {
    return settings?.userSignature ?? ""
}
```

<div dir="rtl" align="right">

**ليش:** `settings` بتنملى فقط لما فلاتر ينادي `config_downloader`. لكن iOS بيشغّل التطبيق بالخلفية لتسليم تحميل خلص، **قبل** ما فلاتر يشتغل أصلاً. وقتها `settings` بتكون `nil` وقراءتها بتعمل crash.

**السيناريو:** المستخدم بلّش تحميل ثم سكّر التطبيق. خلص التحميل بالخلفية → iOS شغّل التطبيق بصمت لتسليم الملف → الكود القديم بيقرأ `settings.userSignature` وهي `nil` → انهيار صامت، والملف ما بينحفظ.

**أثر على الريسبونس:** لا يوجد. هذا حماية من انهيار.

## 1-3. `config()` — الاسترجاع بعد ما تردّ الجلسة

</div>

**قبل**

```swift
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
```

**بعد**

```swift
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
```

<div dir="rtl" align="right">

**ليش:** الحلقة القديمة كانت بتشتغل **قبل** ما نعرف شو الجلسة لسه بتحمّله (`getAllTasks` غير متزامنة)، فممكن تبلّش نسخة ثانية من تحميل شغال. وكمان كانت بتمسح السجل فوراً (`clearTempDataFor`) — يعني حتى لو نجح الاسترجاع، ما بقي أي أثر لو صار شي بعدها.

**السيناريو:** التطبيق فتح وفيه تحميلين شغالين من قبل. الكود القديم بيقرأ السجلات ويبلّش تحميلهم من جديد فوراً، بينما النظام أصلاً بيحمّلهم → تحميل مزدوج لنفس الملف واستهلاك مضاعف للبيانات.

**أثر على الريسبونس:** لا يوجد في الشكل. الأثر: ما عاد يصير تحميل مكرر.

## 1-4. `startDownload` — الجلسة والسجل واستكمال البايتات

</div>

**قبل**

```swift
public func startDownload(url: URL, forMediaId id :Int, mediaName: String = "",
                          type: MediaManager.MediaType, mediaGroup: MediaGroup?,
                          object: [String:Any]? = nil, shouldStart : Bool = true)->URLSessionDownloadTask? {
    if !configed {return nil}
    if tasks.contains(where: {$0.currentRequest?.url == url}) {
        return nil
    }

    let task = foregroundUrlSession.downloadTask(with: url)

    task.taskDescription = mediaName
    task.mediaId = "\(id)_\(type.version_3_value)_\(userSignature)"
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
```

**بعد**

```swift
public func startDownload(url: URL, forMediaId id :Int, mediaName: String = "",
                          type: MediaManager.MediaType, mediaGroup: MediaGroup?,
                          object: [String:Any]? = nil, shouldStart : Bool = true)->URLSessionDownloadTask? {
    if !configed {return nil}
    let taskId = "\(id)_\(type.version_3_value)_\(userSignature)"

    // Match on the media id too: the same media can come back with a freshly signed URL.
    if tasks.contains(where: {$0.mediaId == taskId || $0.originalRequest?.url == url}) {
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
    if shouldStart{
        task.resume()
    }
    tasks.append(task)

    if let object = object, let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted){
        UserDefaults.standard.set(data, forKey: taskId)
    }
    mediaGroup?.register()
    // Persist the download before anything else can go wrong.
    persistRecord(for: task, url: url, status: shouldStart ? .running : .suspended)
    retryDelay = DownloadManager.firstRetryDelay
    return task
}
```

<div dir="rtl" align="right">

**ليش (أربع نقاط):**

1. المهمة رجعت للجلسة الخلفية (نفس سبب البلوك 1-1).
2. منع التكرار صار على **رقم الميديا** كمان مش على الرابط فقط — لأن نفس الفيلم بيجي برابط موقّع جديد كل مرة، فالمقارنة بالرابط ما بتمسك التكرار.
3. لو في بايتات محفوظة من محاولة فشلت، بنكمّل من عندها بدل ما نبلّش من الصفر.
4. بنكتب سجل للتحميل على القرص فوراً — هذا السجل هو اللي بيخلّي العنصر يرجع لو التطبيق انقتل أو الجلسة نسيت المهمة.

**السيناريو:** المستخدم يحمّل فيلم 2 جيجا، وصل 70%، سكّر التطبيق بالسحب. بالقديم: راح كل شي. بالجديد: السجل موجود، والتحميل بيرجع من عند 70% (شفناها فعلياً: `Range: bytes=112656384-`).

**أثر على الريسبونس:** لا يوجد. `startDownload` بترجّع نفس النوع، و`start_download_movie` بترجّع نفس الليست بنفس الشكل.

## 1-5. `updateTasks` — دمج بدل استبدال

</div>

**قبل**

```swift
func updateTasks() {
    urlSession.getAllTasks { tasks in
        DispatchQueue.main.async {
            self.tasks = tasks.filter({$0.state != .completed})
            self.didLoadPreListedTasks?()
        }
    }
}
```

**بعد**

```swift
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
```

<div dir="rtl" align="right">

**ليش:** `getAllTasks` بترجّع **لقطة** من لحظة السؤال. الاستبدال الكامل بيرمي أي تحميل بدأ بين لحظة السؤال ولحظة الجواب. وبعد الكوميت الخاطئ صار الجواب فاضي دائماً (لأن المهام على جلسة ثانية) → الليست بتتفضّى بالكامل مع كل `config`.

**السيناريو (وهو سيناريو مشكلتك حرفياً):** التطبيق يرجع للواجهة → ينادي `config_downloader` → `updateTasks` بتسأل الجلسة الخلفية → بترجّع صفر مهام (لأنها كلها على الفورجراوند) → `self.tasks = []` → الليست فضيت والتحميل شغال.

**السيناريو الثاني (حتى بدون الكوميت الخاطئ):** التطبيق فتح، بعد 5 ملّي ثانية المستخدم ضغط تحميل، وبعد 120 ملّي ثانية وصل جواب سؤال قديم ما فيه هالمهمة → المهمة انمسحت من الذاكرة رغم إنها شغالة.

**السيناريو الثالث (`.canceling`):** المستخدم يلغي تحميل → المهمة بتضل بحالة "قيد الإلغاء" لحظات → أي `updateTasks` بهاي اللحظة كانت بترجّعها للّيست كصف فاضي بدون بيانات لثانية أو ثانيتين. (هاي انمسكت فعلياً أثناء تشغيل الاختبارات.)

**أثر على الريسبونس:** لا يوجد في الشكل. الأثر: العنصر ما بيختفي وما بيتكرر وما بيرجع بعد الإلغاء.

## 1-6. هوية المهمة (`URLSessionTask` extension)

</div>

**قبل**

```swift
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
```

**بعد**

```swift
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
```

<div dir="rtl" align="right">

**ليش:** `taskIdentifier` رقم فريد **داخل الجلسة الواحدة فقط**، وبيتعاد استخدامه بين تشغيلة وتشغيلة. يعني مفتاح `task_id_3` من الأسبوع الماضي ممكن يوصف مهمة مختلفة تماماً اليوم. أما `taskDescription` فـ URLSession بترجّعه مع المهمة نفسها بعد إعادة تشغيل التطبيق.

**السيناريو:** المستخدم كان محمّل فيلم (مهمة رقم 2) وخلص. اليوم بلّش حلقة، وأخذت رقم 2 كمان. الكود القديم بيقرأ المفتاح القديم → الحلقة بتظهر باسم الفيلم أو بتتخزّن بمكان الفيلم.

**التوافق مع النسخ القديمة:** لو المستخدم محدّث المكتبة وعنده تحميلات بدأت بالنسخة القديمة، الـ getter بيرجع يقرأ المفتاح القديم تلقائياً — فما بتضيع.

**أثر على الريسبونس:** لا يوجد. `mediaId` بيوصل لفلاتر بنفس القيمة والشكل، بس بمصدر أوثق.

## 1-7. `extractMedia` — قراءة الاسم والنوع

</div>

**قبل**

```swift
let pureType = task.mediaId?.components(separatedBy: "_")[1]

var obj = DownloadedMedia(mediaId: pureID ?? "", name: task.taskDescription ?? "Untitled Media",
                          status: task.state, progress: task.progress.fractionCompleted)

if pureType != "movies"{
    obj.mediaType = .series
    obj.mediaRetrivalType = .EpisodeInfo
}
```

**بعد**

```swift
let pureType = task.mediaType
let name = task.mediaName.isEmpty ? "Untitled Media" : task.mediaName

var obj = DownloadedMedia(mediaId: pureID ?? "", name: name,
                          status: task.state, progress: task.progress.fractionCompleted)

if pureType != .movie{
    obj.mediaType = .series
    obj.mediaRetrivalType = .EpisodeInfo
}
```

<div dir="rtl" align="right">

**ليش:** سطرين مرتبطين بالبلوك السابق. `components(separatedBy: "_")[1]` بتعمل crash لو الـ id ما فيه شرطة سفلية (مهمة قديمة أو تالفة)، وصار في دالة آمنة بدالها. والاسم صار يُقرأ من الجزء المخصص له في `taskDescription` بدل ما يُقرأ الوصف كامل (اللي صار يحتوي الهوية كمان).

**أثر على الريسبونس:** لا يوجد — `name` و `mediaType` و `mediaRetrivalType` بترجع بنفس القيم بالضبط (مثبتة بالمقارنة في القسم 0).

## 1-8. تسليم التحميل المكتمل (`didFinishDownloadingTo`)

</div>

**قبل**

```swift
public func urlSession(_: URLSession, downloadTask d: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    let  pureID = d.mediaId?.components(separatedBy: "_").first
    let pureType = d.mediaId?.components(separatedBy: "_")[1]

    var obj = DownloadedMedia(mediaId: pureID ?? "", name: d.taskDescription ?? "Untitled Media", tempPath: location)
    ...
    do{
        try obj.store(signature: userSignature)     // settings may be nil here
    }catch{
        print("Error:\(error)")
    }
    print("finished")
}
```

**بعد**

```swift
public func urlSession(_: URLSession, downloadTask d: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    // A 4xx/5xx body is an error page, not the media.
    if let response = d.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
        print("download answered with status \(response.statusCode)")
        let failedIdentifier = d.taskIdentifier
        let stillWanted = (d.mediaId.map({ FilesManager.shared.hasTempData(id: $0, user: d.mediaSignature ?? userSignature) })) ?? false
        DispatchQueue.main.async {
            self.tasks.removeAll(where: {$0.taskIdentifier == failedIdentifier})
            if stillWanted {
                self.persistRecord(for: d, status: .suspended)
            }
        }
        return
    }

    let  pureID = d.mediaId?.components(separatedBy: "_").first
    let pureType = d.mediaType
    // iOS can relaunch the app in the background to deliver this callback, long before
    // Flutter calls config_downloader. Read the owner from the task itself.
    let signature = d.mediaSignature ?? userSignature
    ...
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
    }
}
```

<div dir="rtl" align="right">

**ليش (ثلاث نقاط):**

1. **التوقيع من المهمة نفسها:** الهوية أصلاً بتحتوي التوقيع بصيغة `<id>_<type>_<userId>_<profileId>`، فبنقرأه منها بدل ما نعتمد على إعدادات ممكن تكون فاضية.
2. **فحص كود HTTP:** URLSession بتعتبر رد 403 "تحميل ناجح" وبتسلّم جسم الرد كملف. بدون هالفحص بتتخزن صفحة خطأ كأنها فيلم.
3. **تنظيف السجل بعد النجاح** حتى ما يبقى العنصر بالليست كأنه لسه بيحمّل.

**السيناريو الأول:** التحميل خلص والتطبيق مسكّر → iOS شغّله بالخلفية للتسليم → بالقديم الملف بينحفظ تحت توقيع فاضي، فالمستخدم بيفتح التطبيق وما بيلاقي الفيلم أبداً رغم إنه متحمّل ومساحته مأخوذة. هذا سبب جذري ثاني لشكوى «بيتحمل وما بيظهر».

**السيناريو الثاني:** رابط التحميل الموقّع انتهت صلاحيته (`expires` بروابطكم) → السيرفر بيرد 403 → بالقديم بينحفظ ملف 4 كيلوبايت كفيلم "متحمّل" ما بيشتغل، وما في طريقة يعيد المستخدم تحميله لأن التطبيق شايفه مكتمل.

**أثر على الريسبونس:** الشكل ما تغيّر. التغيير الوحيد: الميديا اللي رجعت خطأ HTTP صارت تظهر `status = 1` (موقوفة) بدل ما تظهر مكتملة وهي فاضية.

## 1-9. فشل التحميل (`didCompleteWithError`)

</div>

**قبل**

```swift
public func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    task.mediaId = nil
    if let error = error {
        print("error : \(error)")
    } else {
        print("Finish")
    }
}
```

**بعد**

```swift
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

    // Keep the record so the media stays in the list, but never turn a paused download back on.
    let wasPaused = record.retrivalStatus == URLSessionTask.State.suspended.rawValue
    let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    DispatchQueue.main.async {
        self.tasks.removeAll(where: {$0.taskIdentifier == failedIdentifier})
        guard !self.tasks.contains(where: {$0.mediaId == taskId}) else {return}

        if let resumeData = resumeData {
            FilesManager.shared.saveResumeData(resumeData, id: taskId, user: signature)
        }
        self.persistRecord(for: task, status: wasPaused ? .suspended : .running)
        if !wasPaused {
            self.scheduleRetry()
        }
    }
}
```

<div dir="rtl" align="right">

**ليش:** السطر الأول بالقديم `task.mediaId = nil` كان **بيقطع الحبل** بين المهمة والميديا عند أي خطأ. بعدها `extractMedia` بترجّع عنصر بـ id فاضي وبدون بيانات، والفلتر في `getAllMedia` بيرميه برا الليست → اختفاء نهائي.

**السيناريو:** المستخدم بالمصعد، الشبكة قطعت لثانيتين → التحميل بيفشل → الهوية بتنمسح → العنصر بيختفي من الليست وما بيرجع حتى لو رجعت الشبكة، وما في أي أثر لإعادة المحاولة. هذا حرفياً «النت فصل ورجع والليست اختفت».

**بعد التعديل:** الهوية بتضل، والسجل بيضل، والبايتات المحمّلة بتنحفظ، وبتنجدول إعادة محاولة تلقائية. والتحميل اللي المستخدم أوقفه بإرادته ما بيرجع يشتغل لحاله.

**أثر على الريسبونس:** لا يوجد في الشكل. الأثر: العنصر بيضل ظاهر بدل ما يختفي.

## 1-10. الإيقاف والاستئناف والإلغاء

</div>

**قبل**

```swift
func pauseDownload(forTaskID id: String){
    if !configed {return}
    tasks.first(where: {$0.mediaId == id})?.suspend()
}

func resumeDownload(forTaskID id: String){
    if !configed {return}
    tasks.first(where: {$0.mediaId == id})?.resume()
}

func cancelTask(withID id: String){
    if !configed {return}
    tasks.first(where: {$0.mediaId == id})?.cancel()
    tasks.removeAll(where: {$0.mediaId == id})
}
```

**بعد**

```swift
func pauseDownload(forTaskID id: String){
    if !configed {return}
    guard let task = tasks.first(where: {$0.mediaId == id}) else {return}
    task.suspend()
    // Remember the paused state so a restart after a relaunch does not resume it.
    persistRecord(for: task, status: .suspended)
}

func resumeDownload(forTaskID id: String){
    if !configed {return}
    guard let task = tasks.first(where: {$0.mediaId == id}) else {
        // Nothing live to resume: the transfer died while the app was away, restart it.
        if var record = pendingRecords().first(where: {"\($0.mediaId)_\($0.mediaType.version_3_value)_\(userSignature)" == id}) {
            record.retrivalStatus = URLSessionTask.State.running.rawValue
            _ = record.reCallRequest()
        }
        return
    }
    task.resume()
    persistRecord(for: task, status: .running)
}

func cancelTask(withID id: String){
    if !configed {return}
    // Clear the record first: the cancellation callback must not resurrect the download.
    clearRecord(forTaskId: id, signature: userSignature)
    UserDefaults.standard.removeObject(forKey: id)
    tasks.first(where: {$0.mediaId == id})?.cancel()
    tasks.removeAll(where: {$0.mediaId == id})
}
```

<div dir="rtl" align="right">

**ليش:** الحالة (موقوف / شغال) صار لازم تنكتب على القرص عشان تصمد بعد إعادة تشغيل التطبيق. و«استئناف» تحميل ماتت مهمته كان بيعمل لا شي (لأن ما في مهمة بالذاكرة). والإلغاء كان بيسيب بيانات الميديا في `UserDefaults` للأبد.

**السيناريو:** المستخدم أوقف تحميل، سكّر التطبيق، فتحه بعد يوم → بالقديم الحالة ضاعت؛ بالجديد بيضل موقوف. ولو ضغط "استئناف" على تحميل ماتت مهمته، بالقديم ما بيصير شي أبداً؛ بالجديد بيرجع يشتغل من مكانه.

**أثر على الريسبونس:** لا يوجد. `pause_download` و `resume_download` و `cancel_download` بترجّعوا نفس الليست بنفس الشكل (مقيس في القسم 0: `status=1` للموقوف و `status=0` للشغال، تماماً مثل القديم).

## 1-11. بناء الليست (`getAllMedia` وأخواتها)

</div>

**قبل**

```swift
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
    ...
}
```

**بعد**

```swift
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

/// A record keeps the information needed to restart the transfer, which a live task does not
/// carry. The app must receive the same payload for a media wherever the entry came from, so
/// those extra fields are dropped on the way out.
private func asListEntry(_ record: DownloadedMedia) -> DownloadedMedia {
    var entry = record
    entry.mediaURL = nil
    entry.retrivalStatus = nil
    return entry
}
```

<div dir="rtl" align="right">

**ليش:** صار في مصدر ثاني للعناصر (السجلات على القرص)، فلازم يندمج مع المهام الحية بدون تكرار. و`asListEntry` بتشيل الحقلين اللي بيحملهم السجل ولا بتحملهم المهمة الحية، عشان **الريسبونس يطلع نفسه بالضبط** أياً كان مصدر العنصر.

**السيناريو:** بدون `asListEntry` كان عنصر مسترجع من القرص بيوصل لفلاتر ومعه مفتاحين زيادة (`mediaURL` و `retrivalStatus`). قسته فعلياً وشلته. هذا بالضبط اللي بتخاف منه، وهو مقفول الآن باختبارين بيقارنوا المفاتيح مقارنة تامة.

**أثر على الريسبونس:** صفر فرق في المفاتيح — مثبت بالقياس. الفرق الوحيد إن العنصر بيضل ظاهر بحالات كان بيختفي فيها.

## 1-12. `saveDownloadStatus` — ما عادت تلغي التحميلات

</div>

**قبل**

```swift
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
```

**بعد**

```swift
public func saveDownloadStatus(){
    tasks.forEach({ task in
        persistRecord(for: task)
    })
}
```

<div dir="rtl" align="right">

**ليش:** الدالة القديمة كانت **بتلغي كل التحميلات** بعد حفظها، وهذا آخر شي بدنا إياه مع جلسة خلفية بتكمّل لحالها. كمان الفحوصات القديمة كلها كانت بلا معنى (`downloadTask != nil` على قيمة غير اختيارية).

**مهم:** هالدالة **ما إلها ولا مُنادي** في المكتبة كلها ولا هي معروضة على قناة الميثود، يعني تطبيق فلاتر ما بيقدر يناديها أصلاً. التغيير آمن تماماً.

**أثر على الريسبونس:** لا يوجد.

## 1-13. إضافات جديدة كلياً (ما كانت موجودة بأي شكل)

| الإضافة | شو بتعمل | ليش |
| --- | --- | --- |
| `restorePendingDownloads()` | بتعيد تشغيل أي تحميل عنده سجل وما عنده مهمة حية | استرجاع بعد قتل التطبيق أو موت الاتصال |
| `scheduleRetry()` | إعادة محاولة بعد 10 ثواني، وبتتضاعف لحد 5 دقائق | التعافي كان بيتطلب من المستخدم يعيد فتح التطبيق |
| `scheduleStallCheck()` + `restartStalledTasks()` | كل 30 ثانية بتفحص المهام الشغالة؛ اللي ما استقبلت ولا بايت بفحصين متتاليين بتعيد تشغيلها من مكانها | مقاس عملياً: iOS بيسيب المهمة "شغالة" للأبد بعد ما يموت الاتصال بدون ما يبلّغ خطأ |
| `startNetworkMonitoring()` | لما ترجع الشبكة، بتشتغل جولة استرجاع | يلتقط اللي النظام تخلّى عنه أثناء الانقطاع |
| `recoverMissingIdentities()` | بتعيد ربط مهمة فقدت هويتها بالسجل عبر الرابط | حزام أمان للمهام اللي رجعت من نسخ قديمة |
| `persistRecord` / `clearRecord` | كتابة ومسح سجل التحميل | أساس كل الإصلاح |

**أثر على الريسبونس:** كلها خلفية. لا تضيف ولا تحذف أي مفتاح.

## 1-14. مداخل للاختبار فقط

`sessionIdentifierOverride` و `simulateAppRelaunch` و `forgetConfiguration` و `stallCheckInterval`.

كلها `internal` — يعني مرئية للاختبارات فقط وغير موجودة في الواجهة العامة للمكتبة، وتطبيق فلاتر ما بيقدر يشوفها ولا يستدعيها.

</div>

---

<div dir="rtl" align="right">

# الملف الثاني: `ios/Classes/Managers/FilesManager.swift`

خمس تعديلات، كلها إضافات أو تصحيحات داخلية. **ولا واحد فيها بيلمس شكل الريسبونس.**

## 2-1. دوال قراءة السجل

</div>

**بعد (جديد بالكامل)**

```swift
func hasTempData(id: String, user: String)->Bool{
    let fullPath = cache.appendingPathComponent(user).appendingPathComponent(id + ".keetmp")
    return checkFileExistance(filePath: fullPath.path)
}

func getTempData(id: String, user: String)->DownloadedMedia?{
    let fullPath = cache.appendingPathComponent(user).appendingPathComponent(id + ".keetmp")
    guard let data = try? Data(contentsOf: fullPath) else {return nil}
    return try? JSONDecoder().decode(DownloadedMedia.self, from: data)
}
```

<div dir="rtl" align="right">

**ليش:** لما تفشل مهمة، لازم نعرف: هل هذي الميديا لسه مطلوبة (يعني المستخدم ما ألغاها)؟ وشو كانت حالتها (موقوفة ولا شغالة)؟ قراءة ملف واحد أرخص من قراءة كل السجلات.

**السيناريو:** المستخدم ضغط "إلغاء" → بنمسح السجل → بعدها بجزء من الثانية بتوصل رسالة الإلغاء من النظام → بدون هالفحص كان الكود بيعيد إنشاء السجل، فالتحميل الملغي بيرجع للحياة عند أول `config`.

## 2-2. تخزين البايتات المحمّلة (resume data)

</div>

**بعد (جديد بالكامل)**

```swift
/// Bytes iOS hands back when a transfer fails, so the download can continue instead of
/// starting over.
func saveResumeData(_ data: Data, id: String, user: String){ ... }   // writes <id>.keeresume
func getResumeData(id: String, user: String)->Data?{ ... }
func clearResumeData(id: String, user: String){ ... }
```

<div dir="rtl" align="right">

**ليش:** بدونها كل انقطاع بيعني إعادة تحميل الفيلم من الصفر.

**السيناريو:** فيلم 2 جيجا وصل 1.8 جيجا وانقطع النت. بالقديم: يبلّش من الصفر (1.8 جيجا راحت هدر من باقة المستخدم). بالجديد: بيكمّل من 1.8.

## 2-3. `getTempData(user:)` — فلترة الملفات وتعبئة التوقيع

</div>

**قبل**

```swift
for file in contentsList ?? [] {
    if let data = try? Data(contentsOf: file){
        if var media = try? JSONDecoder().decode(DownloadedMedia.self, from: data) {
            media.status = media.retrivalStatus == 0 ? .running : .suspended
            list.append(media)
        }
    }
}
```

**بعد**

```swift
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
```

<div dir="rtl" align="right">

**ليش:** نفس المجلد صار فيه ملفات `.keeresume` كمان، فلازم نتجاهلها بدل ما نحاول نفكّها كـ JSON. و`setUser` ضرورية لأن العنصر بيحسب مسار ملفه من التوقيع.

**أثر على الريسبونس:** لا يوجد — التوقيع ما بينرسل لفلاتر أصلاً (مش ضمن `CodingKeys`).

## 2-4. تصحيح فحص وجود المجلد

</div>

**قبل**

```swift
if checkFolderExistance(dir: dirPath.absoluteString) == false {
```

**بعد**

```swift
if checkFolderExistance(dir: dirPath.path) == false {
```

<div dir="rtl" align="right">

**ليش:** `absoluteString` بترجّع `file:///Users/...` (رابط)، و`FileManager` بدها مسار `/Users/...`. الفحص كان بيفشل دائماً فيحاول ينشئ المجلد كل مرة. غير مؤذي (الإنشاء بيتجاهل الموجود) بس غلط، وصُلح لأننا صرنا نستخدم نفس المجلد بكثافة.

**أثر على الريسبونس:** لا يوجد.

## 2-5. حذف `print` من `saveTempData`

كانت بتطبع مسار كل ملف وكلمة "Done". صارت تنكتب مع كل بدء/إيقاف/فشل تحميل، فشيلتها. **أثر على الريسبونس:** لا يوجد.

</div>

---

<div dir="rtl" align="right">

# الملف الثالث: `ios/Classes/Data Models/DownloadedMedia.swift`

تعديل واحد فقط، ستة أسطر محذوفة.

</div>

**قبل**

```swift
func reCallRequest()->String?{
    if let url = mediaURL {
        if let task = DownloadManager.shared.startDownload(...){

            DownloadManager.shared.updateTasks()

//                if retrivalStatus == 1 {
//                    task.suspend()
//                }
            return task.mediaId
        }
    }
    return nil
}
```

**بعد**

```swift
func reCallRequest()->String?{
    if let url = mediaURL {
        if let task = DownloadManager.shared.startDownload(...){
            return task.mediaId
        }
    }
    return nil
}
```

<div dir="rtl" align="right">

**ليش:** `startDownload` أصلاً بتضيف المهمة للّيست بشكل متزامن. النداء الزائد كان بيطلق تحديث غير متزامن لكل ميديا يتم استرجاعها — وبالسلوك القديم (الاستبدال) كان ممكن يمسح المهمة اللي لسه أنشأها.

**السيناريو:** استرجاع 5 تحميلات عند فتح التطبيق → 5 تحديثات متوازية، كل واحد بلقطة قديمة → الليست بترجّع أرقام مختلفة كل ثانية.

**أثر على الريسبونس:** لا يوجد في الشكل — بس الليست صارت مستقرة.

</div>

---

<div dir="rtl" align="right">

# ملفات تطبيق المثال والاختبارات

**ولا واحد من هدول بينزل مع المكتبة للمستخدمين.** كلهم داخل `example/` أو مشروع الاختبار.

| الملف | التغيير | ليش |
| --- | --- | --- |
| `example/ios/RunnerTests/DownloadManagerTests.swift` | جديد — 16 اختبار | يغطّي الاختفاء، إعادة التشغيل، قتل التطبيق، الانقطاع، التجمّد، ردود الخطأ، الإيقاف، الإلغاء، تجميع المسلسلات، الهوية، وشكل الريسبونس |
| `example/ios/RunnerTests/ResponseShapeSnapshotTests.swift` | جديد | بيطبع شكل كل ريسبونس؛ بيشتغل على النسخة القديمة والجديدة عشان المقارنة في القسم 0 |
| `example/ios/RunnerTests/LocalHTTPServer.swift` | جديد | سيرفر HTTP داخل الاختبار: بيبطّئ، بيدعم Range، بيقطع الاتصال، وبيعلّقه |
| `example/ios/Runner.xcodeproj/project.pbxproj` | إضافة هدف `RunnerTests` | ما كان في أي هدف اختبار بالمشروع |
| `example/ios/Runner.xcodeproj/.../Runner.xcscheme` | ربط الاختبارات بالـ scheme | عشان `xcodebuild test` يشغّلها |
| `example/ios/Podfile` (+ `Podfile.lock`) | هدف `RunnerTests` و `ENABLE_TESTABILITY` للـ Debug | يلزم `@testable import dowplay` |
| `example/ios/Runner/Info.plist` | استثناء ATS لـ `127.0.0.1` | السيرفر المحلي بالاختبار HTTP عادي. تطبيق المثال فقط |

</div>

---

<div dir="rtl" align="right">

# خلاصة: هل في أي تغيير بيوصل لتطبيق الموبايل؟

| النوع | الجواب |
| --- | --- |
| أسماء الميثودز على قناة الاتصال | ما تغيّرت |
| الوسائط (arguments) | ما تغيّرت |
| مفاتيح الريسبونس | **ما تغيّرت** — مقيسة على 9 ريسبونسات في 3 نسخ |
| أنواع القيم | ما تغيّرت |
| `status` و `mediaType` و `mediaRetrivalType` | نفس القيم بالضبط |
| `object` و `group` | نفس المفاتيح بالضبط |
| `progress` | نفس المفتاح والنوع، بس صار يعطي التقدّم الحقيقي بدل صفر |
| السلوك | العنصر بيضل ظاهر لحد ما يخلص أو تلغيه؛ والميديا اللي رجعت خطأ HTTP بتظهر `status = 1` بدل "مكتملة" |

يعني: تطبيق الموبايل بيحدّث المكتبة وخلص، بدون أي تعديل بكود Dart.

## كيف تتحقق بنفسك

</div>

```sh
# 1) كل الاختبارات
cd example/ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'id=<simulator-udid>' -only-testing:RunnerTests

# 2) شكل الريسبونس فقط
xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'id=<simulator-udid>' \
  -only-testing:RunnerTests/ResponseShapeSnapshotTests | grep '^SHAPE|'
```

<div dir="rtl" align="right">

لمقارنة الريسبونس مع نسخة قديمة: بدّل ملفات المكتبة الثلاثة بنسختها من الكوميت المطلوب، عطّل `DownloadManagerTests.swift` مؤقتاً (لأنه بيستخدم دوال جديدة)، شغّل نقطة 2، ثم رجّع الملفات. هيك بالضبط انعملت الجداول في القسم 0.

</div>

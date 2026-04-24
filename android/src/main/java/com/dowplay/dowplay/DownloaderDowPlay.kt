package com.dowplay.dowplay

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.util.Log
import android.view.LayoutInflater
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import com.downloader.PRDownloader
import com.downloader.Status
import com.dowplay.dowplay.databinding.ExplanationPermissionBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.io.File
import java.math.BigInteger
import java.security.SecureRandom


@UnstableApi class DownloaderDowPlay(initContext: Context, initActivity: Activity, initLang: String) :
    ActivityAware {

    private var context: Context
    private var lactivity: Activity
    private var lLang: String

    init {
        context = initContext
        lactivity = initActivity
        lLang = initLang
    }

    fun generateRandomToken(length: Int): String {
        val secureRandom = SecureRandom()
        val token = BigInteger(130, secureRandom).toString(32)
        return token.take(length)
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
////FOR Permission
    var myRequestCode = 1997
    var permissionToDownload = false

//    private fun showDownloadStatePermission() {
//        if ((ContextCompat.checkSelfPermission(
//                context,
//                Manifest.permission.READ_EXTERNAL_STORAGE
//            ) != PackageManager.PERMISSION_GRANTED
//                    || ContextCompat.checkSelfPermission(
//                context,
//                Manifest.permission.WRITE_EXTERNAL_STORAGE
//            ) != PackageManager.PERMISSION_GRANTED)
//            && (ContextCompat.checkSelfPermission(
//                context,
//                Manifest.permission.READ_MEDIA_VIDEO
//            ) != PackageManager.PERMISSION_GRANTED
//                    || ContextCompat.checkSelfPermission(
//                context,
//                Manifest.permission.READ_MEDIA_IMAGES
//            ) != PackageManager.PERMISSION_GRANTED)
//        ) {
//            val permissionsArray = arrayOf(
//                Manifest.permission.READ_EXTERNAL_STORAGE,
//                Manifest.permission.WRITE_EXTERNAL_STORAGE,
//                Manifest.permission.READ_MEDIA_VIDEO,
//                Manifest.permission.READ_MEDIA_IMAGES,
//                Manifest.permission.POST_NOTIFICATIONS
//            )
//            if (ActivityCompat.shouldShowRequestPermissionRationale(
//                    lactivity,
//                    Manifest.permission.READ_EXTERNAL_STORAGE
//                )
//                || ActivityCompat.shouldShowRequestPermissionRationale(
//                    lactivity,
//                    Manifest.permission.WRITE_EXTERNAL_STORAGE
//                )
//                || ActivityCompat.shouldShowRequestPermissionRationale(
//                    lactivity,
//                    Manifest.permission.READ_MEDIA_VIDEO
//                )
//                || ActivityCompat.shouldShowRequestPermissionRationale(
//                    lactivity,
//                    Manifest.permission.READ_MEDIA_IMAGES
//                )
//                || ActivityCompat.shouldShowRequestPermissionRationale(
//                    lactivity,
//                    Manifest.permission.POST_NOTIFICATIONS
//                )
//            ) {
//
//                if (lLang.equals("en", ignoreCase = true)) {
//                    showExplanationForMediaFilePermission(
//                        "Permission Needed",
//                        "Media and file access must be granted to start downloading movies and series through the app permissions option",
//                        permissionsArray,
//                        true
//                    )
//                } else {
//                    showExplanationForMediaFilePermission(
//                        "منح الإذن",
//                        "يجب منح صلاحية الوصول للوسائط والملفات لبدء تحميل الافلام والمسلسلات من خلال خيار اذونات التطبيق",
//                        permissionsArray,
//                        true
//                    )
//                }
//            } else {
//                if (lLang.equals("en", ignoreCase = true)) {
//                    showExplanationForMediaFilePermission(
//                        "Permission Needed",
//                        "You must grant access to media and files to start downloading movies and series",
//                        permissionsArray,
//                        false
//                    )
//                } else {
//                    showExplanationForMediaFilePermission(
//                        "منح الإذن",
//                        "يجب منح صلاحية الوصول للوسائط والملفات لبدء تحميل الافلام والمسلسلات",
//                        permissionsArray,
//                        false
//                    )
//                }
//            }
//        } else {
//            permissionToDownload = true
//        }
//        ////////////////////////////////////////////////
//        ////////////////////////////////////////////////
//        if (ContextCompat.checkSelfPermission(
//                context,
//                Manifest.permission.POST_NOTIFICATIONS
//            ) != PackageManager.PERMISSION_GRANTED
//        ) {
//            if (ActivityCompat.shouldShowRequestPermissionRationale(
//                    lactivity,
//                    Manifest.permission.POST_NOTIFICATIONS
//                )
//            ) {
//                if (lLang.equals("en", ignoreCase = true)) {
//                    showExplanationForMediaFilePermission(
//                        "Permission Needed",
//                        "Alerts must be granted to be able to receive notifications through the app permissions option",
//                        arrayOf(
//                            Manifest.permission.POST_NOTIFICATIONS
//                        ),
//                        true
//                    )
//                } else {
//                    showExplanationForMediaFilePermission(
//                        "منح الإذن",
//                        "يجب منح صلاحية التنبيهات حتى تتمكن من استقبال الإشعارات من خلال خيار اذونات التطبيق",
//                        arrayOf(
//                            Manifest.permission.POST_NOTIFICATIONS
//                        ), true
//                    )
//                }
//
//            } else {
//                if (lLang.equals("en", ignoreCase = true)) {
//                    showExplanationForMediaFilePermission(
//                        "Permission Needed",
//                        "Alerts must be granted to be able to receive notifications",
//                        arrayOf(
//                            Manifest.permission.POST_NOTIFICATIONS
//                        ), false
//                    )
//                } else {
//                    showExplanationForMediaFilePermission(
//                        "منح الإذن",
//                        "يجب منح صلاحية التنبيهات حتى تتمكن من استقبال الإشعارات",
//                        arrayOf(
//                            Manifest.permission.POST_NOTIFICATIONS
//                        ), false
//                    )
//                }
//            }
//        }
//    }

    private fun showDownloadStatePermission() {
        // Storage permissions are NOT needed — files are saved to context.filesDir (private storage),
        // which is always accessible without any runtime permissions on all Android versions.
        permissionToDownload = true

        // Only POST_NOTIFICATIONS is required (for showing download progress notification)
        if (ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            if (ActivityCompat.shouldShowRequestPermissionRationale(
                    lactivity,
                    Manifest.permission.POST_NOTIFICATIONS
                )
            ) {
                showExplanationForMediaFilePermission(
                    if (lLang.equals("en", ignoreCase = true)) "Permission Needed" else "منح الإذن",
                    if (lLang.equals("en", ignoreCase = true))
                        "Alerts must be granted to be able to receive notifications through the app permissions option"
                    else
                        "يجب منح صلاحية التنبيهات حتى تتمكن من استقبال الإشعارات من خلال خيار اذونات التطبيق",
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    true
                )
            } else {
                showExplanationForMediaFilePermission(
                    if (lLang.equals("en", ignoreCase = true)) "Permission Needed" else "منح الإذن",
                    if (lLang.equals("en", ignoreCase = true))
                        "Alerts must be granted to be able to receive notifications"
                    else
                        "يجب منح صلاحية التنبيهات حتى تتمكن من استقبال الإشعارات",
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    false
                )
            }
        }
    }

    private fun showExplanationForMediaFilePermission(
        title: String,
        message: String,
        permissionsArray: Array<String>,
        openSettingScreen: Boolean
    ) {
        val builder = AlertDialog.Builder(lactivity, R.style.ScreenDialogTheme)
        var currentDialog: AlertDialog = builder.create()

        val customDialog =
            LayoutInflater.from(context).inflate(R.layout.explanation_permission, null, false)
        val bindingMF = ExplanationPermissionBinding.bind(customDialog)
        bindingMF.permissionTitle.text = title
        bindingMF.permissionDetails.text = message
        bindingMF.buttonExplanationPermission.text =
            if (lLang.lowercase() == "en") "ok" else "موافق"

        bindingMF.buttonExplanationPermission.setOnClickListener {
            if (openSettingScreen) {
                currentDialog.dismiss()
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                val uri = Uri.fromParts("package", context.packageName, null)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                intent.data = uri
                context.startActivity(intent)
            } else {
                currentDialog.dismiss()
                ActivityCompat.requestPermissions(
                    lactivity, permissionsArray, myRequestCode
                )
            }
        }

        /////////////////////////
        builder.setView(customDialog)
        /*.setTitle(title)
        .setMessage(message)
        .setPositiveButton(
            android.R.string.ok
        ) { dialog, id ->
            if (openSettingScreen) {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                val uri = Uri.fromParts("package", context.packageName, null)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                intent.data = uri
                context.startActivity(intent)
            } else {
                ActivityCompat.requestPermissions(
                    lactivity,
                    arrayOf(
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ),
                    myRequestCode
                )
            }
        }*/
        currentDialog = builder.create()
        currentDialog.show()
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    fun startDownload(
        url: String,
        name: String,
        mediaType: String,
        mediaId: String,
        mediaData: String,
        userId: String,
        profileId: String,
        seasonId: String,
        episodeId: String,
        seasonOrder: String,
        episodeOrder: String,
        seasonName: String,
        episodeName: String,
        episodeJson: String,
        canReturnResultToFlutter:Boolean
    ): Int {
        showDownloadStatePermission()
        if (permissionToDownload) {
            //PRDownloader.initialize(context);
            // Enabling database for resume support even after the application is killed:
            //val url1 = "https://thekee.gcdn.co/video/m-159n/English/Animation&Family/The.Simpsons.in.Plusaversary.2021.1080.mp4"
            //var url1 = "https://thekee.gcdn.co/video/m-159n/English/Drama/Deathwatch.2002.1080p.V1.mp4"
            //for save in public pkg app
            //var dirPath = "${context.getExternalFilesDir(null)}"
            //for save in private pkg app

            val downloadInfo = DatabaseHelper(context).getDownloadInfoFromDB(
                if (mediaType == "series") episodeId else mediaId,
                mediaType
            )
            val status: Status =
                PRDownloader.getStatus(downloadInfo["download_id"].toString().trim().toIntOrNull() ?: -1)

            Log.d(
                "startDownload Method",
                "this video is downloaded..."+ status +" > " +downloadInfo["download_id"]+" > "+ mediaId + " > " + mediaType + " > " + downloadInfo["status"]
            )
            if ((downloadInfo["status"] == DownloadManagerSTATUS.STATUS_SUCCESSFUL || status == Status.RUNNING) && downloadInfo["status"] != null) {
                Log.d("startDownload Method", "this video is downloaded...")
                if(canReturnResultToFlutter) {
                    DowplayPlugin.myResultCallback.success(
                        DatabaseHelper(context).getAllDownloadDataFromDB(userId, profileId)
                    )
                }
                return 0
            } else {
                if ((downloadInfo["status"] == DownloadManagerSTATUS.STATUS_RUNNING && status != Status.RUNNING)
                    || (downloadInfo["status"] == DownloadManagerSTATUS.STATUS_PAUSED && status != Status.PAUSED)
                    || (downloadInfo["status"] == DownloadManagerSTATUS.STATUS_FAILED)
                    || status == Status.FAILED
                    || status == Status.CANCELLED
                    || status == Status.UNKNOWN
                    || downloadInfo["status"] == null
                ) {
                    cancelDownload(mediaId, mediaType)
                }
                val dirPath = context.filesDir.path + "/downplay"
                val videoName = generateRandomToken(50) + ".mp4"
                //println("Bom Dir: $dirPath")
                //println("Bom Dir: ${"$dirPath/$videoName"}")
                val intent = Intent(context, DownloadService::class.java).apply {
                    putExtra("url", url)
                    putExtra("dir_path", dirPath)
                    putExtra("video_name", videoName)
                    putExtra("full_path", "$dirPath/$videoName")
                    putExtra("media_type", mediaType)
                    putExtra("media_id", mediaId)
                    putExtra("media_name", name)
                    putExtra("media_data", mediaData)
                    putExtra("user_id", userId)
                    putExtra("profile_id", profileId)
                    putExtra("season_id", seasonId)
                    putExtra("episode_id", episodeId)
                    putExtra("season_order", seasonOrder)
                    putExtra("episode_order", episodeOrder)
                    putExtra("season_name", seasonName)
                    putExtra("episode_name", episodeName)
                    putExtra("episode_json", episodeJson)
                    putExtra("can_return_result_to_flutter", canReturnResultToFlutter)
                    putExtra("lang", lLang)
                }
                context.startService(intent)
                return 1
            }
        } else {
            if(canReturnResultToFlutter) {
                DowplayPlugin.myResultCallback.success(
                    DatabaseHelper(context).getAllDownloadDataFromDB(userId, profileId)
                )
            }
            return 0
        }
    }

    fun pauseDownload(media_id: String, media_type: String) {
        val downloadData = DatabaseHelper(context).getDownloadInfoFromDB(media_id, media_type)
        val downloadId = downloadData["download_id"]
        if (downloadId.toString().trim().isNotEmpty() && downloadId != null) {
            PRDownloader.pause(downloadId.toString().toInt())
        }
    }

    fun resumeDownload(media_id: String, media_type: String) {
        /*
        Status.PAUSED: The download is currently paused.
        Status.RUNNING: The download is currently running.
        Status.QUEUED: The download is queued and waiting for its turn to start.
        Status.COMPLETE: The download has completed successfully.
        Status.CANCELED: The download has been canceled.
        Status.UNKNOWN: The status of the download is unknown or could not be determined.
        */
        val downloadData = DatabaseHelper(context).getDownloadInfoFromDB(media_id, media_type)
        val downloadId = downloadData["download_id"]
        if (downloadId.toString().trim().isNotEmpty() && downloadId != null) {
            PRDownloader.resume(downloadId.toString().toInt())
            ////////////
            //if video has any error....will delete video data
            val status: Status = PRDownloader.getStatus(downloadId.toString().toInt())
            if ((downloadData["status"] == DownloadManagerSTATUS.STATUS_FAILED)
                || status == Status.FAILED
                || status == Status.CANCELLED
                || status == Status.UNKNOWN
            ) {
                cancelDownload(media_id, media_type)
            }
            ///////////
        }
    }

    fun cancelDownload(media_id: String, media_type: String) {
        Log.d("cancelDownload","Start Delete Media...")
        val downloadData = DatabaseHelper(context).getDownloadInfoFromDB(media_id, media_type)
        val downloadId = downloadData["download_id"]
        val videoPath = downloadData["video_path"]
        if (downloadId.toString().trim().isNotEmpty() && downloadId != null) {
            PRDownloader.cancel(downloadId.toString().toInt())
            val file = File(videoPath.toString())
            if (file.exists()) {
                file.delete()
                Log.d("cancelDownload","Start Delete Media...FileISDeleted True")
            }else{
                Log.d("cancelDownload","Start Delete Media...FileISDeleted False")
            }
            DatabaseHelper(context).deleteMediaFromDB(media_id, media_type)
        }
    }

    fun getDownloadMediaByDownloadID(
        media_id: String,
        media_type: String
    ): ArrayList<HashMap<String, Any>> {
        return DatabaseHelper(context).getDownloadDataFromDbByMediaIdAndMediaType(
            media_id,
            media_type
        )
    }

    fun getDownloadMediaInfo(user_id: String, profile_id: String, mediaId:String, mediaType:String, seasonId: String, tvShow: String): List<HashMap<String, Any>> {
        return DatabaseHelper(context).getDownloadDataFromDB(user_id, profile_id,mediaId, mediaType,seasonId,tvShow)
    }

    fun getAllDownloadMedia(user_id: String, profile_id: String): List<HashMap<String, Any>> {
        return DatabaseHelper(context).getAllDownloadDataFromDB(user_id, profile_id)
    }

    fun getAllSeasons(series_id: String): List<HashMap<String, Any>> {
        return DatabaseHelper(context).getAllSeasonsDownloadDataFromDB(series_id)
    }

    fun getAllEpisodes(seasons_id: String, tvshow_id: String): List<HashMap<String, Any>> {
        return DatabaseHelper(context).getAllEpisodesDownloadDataFromDB(seasons_id, tvshow_id)
    }

    ////////////////////////////////////////////////////////////////

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        lactivity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        lactivity = binding.activity
    }

    override fun onDetachedFromActivity() {}
}
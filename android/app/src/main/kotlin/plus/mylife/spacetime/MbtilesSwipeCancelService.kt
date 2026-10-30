package plus.mylife.spacetime

import android.app.NotificationManager
import android.app.Service
import android.app.job.JobScheduler
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.work.WorkManager

/**
 * Watches for Recents swipe-away. [Service.onTaskRemoved] runs while the
 * process is still alive so we can cancel the mbtiles WorkManager/FGS
 * worker and its notification from native code (Dart is already dead).
 *
 * Manifest must set android:stopWithTask="false" or this callback is skipped.
 */
class MbtilesSwipeCancelService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Sticky so the watcher stays up across soft activity recreations.
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved — canceling mbtiles FGS + notification")
        cancelMbtilesDownloadOnSwipeAway(applicationContext)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    companion object {
        private const val TAG = "MbtilesSwipeCancel"

        fun start(context: Context) {
            try {
                context.startService(Intent(context, MbtilesSwipeCancelService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start swipe-cancel watcher", e)
            }
        }

        fun cancelMbtilesDownloadOnSwipeAway(context: Context) {
            try {
                val wm = WorkManager.getInstance(context)
                // background_downloader tags: group=<Task.group>, BackgroundDownloader, taskId=…
                wm.cancelAllWorkByTag("group=mbtiles")
                wm.cancelAllWorkByTag("BackgroundDownloader")
                Log.i(TAG, "Canceled WorkManager mbtiles / BackgroundDownloader work")
            } catch (e: Exception) {
                Log.e(TAG, "WorkManager cancel failed", e)
            }

            try {
                val js = context.getSystemService(JobScheduler::class.java)
                js?.cancelAll()
                Log.i(TAG, "Canceled JobScheduler jobs (UIDT)")
            } catch (e: Exception) {
                Log.e(TAG, "JobScheduler cancel failed", e)
            }

            try {
                val nm = context.getSystemService(NotificationManager::class.java)
                nm?.cancelAll()
                Log.i(TAG, "Canceled all notifications")
            } catch (e: Exception) {
                Log.e(TAG, "Notification cancel failed", e)
            }

            try {
                // Flutter shared_preferences keys are stored with a "flutter." prefix.
                val flutterPrefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE,
                )
                flutterPrefs.edit()
                    .putBoolean("flutter.mbtiles_download_in_progress", false)
                    .remove("flutter.mbtiles_max_partial_bytes")
                    .apply()

                // Drop background_downloader's persisted task / resume maps so a
                // zombie "running" row cannot keep the FGS or auto-resume.
                context
                    .getSharedPreferences(
                        "${context.packageName}_preferences",
                        Context.MODE_PRIVATE,
                    )
                    .edit()
                    .remove("com.bbflight.background_downloader.taskMap.v2")
                    .remove("com.bbflight.background_downloader.resumeDataMap.v2")
                    .remove("com.bbflight.background_downloader.statusUpdateMap.v2")
                    .remove("com.bbflight.background_downloader.progressUpdateMap.v2")
                    .apply()
                Log.i(TAG, "Cleared mbtiles in-progress + downloader task maps")
            } catch (e: Exception) {
                Log.e(TAG, "Prefs cleanup failed", e)
            }
        }
    }
}

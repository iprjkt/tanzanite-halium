package id.tanzanite.switcher

import android.app.WallpaperManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.LocalOverscrollConfiguration
import androidx.compose.foundation.LocalOverscrollFactory
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.example.liquidglass.GlassAccessibilityMode
import com.example.liquidglass.GlassMaterial
import com.example.liquidglass.LiquidGlassTabBar
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.yukonga.miuix.kmp.basic.ButtonDefaults
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.Icon
import top.yukonga.miuix.kmp.basic.MiuixScrollBehavior
import top.yukonga.miuix.kmp.basic.NavigationBar
import top.yukonga.miuix.kmp.basic.NavigationItem
import top.yukonga.miuix.kmp.basic.Scaffold
import top.yukonga.miuix.kmp.basic.SmallTitle
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.basic.TextButton
import top.yukonga.miuix.kmp.basic.TopAppBar
import top.yukonga.miuix.kmp.basic.rememberTopAppBarState
import top.yukonga.miuix.kmp.extra.SuperArrow
import top.yukonga.miuix.kmp.extra.SuperDialog
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.Info
import top.yukonga.miuix.kmp.icon.icons.useful.Like
import top.yukonga.miuix.kmp.icon.icons.useful.NavigatorSwitch
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.darkColorScheme
import top.yukonga.miuix.kmp.theme.lightColorScheme
import top.yukonga.miuix.kmp.utils.MiuixPopupUtils
import top.yukonga.miuix.kmp.utils.overScrollVertical

data class SystemStatus(
    val hasRoot: Boolean = false,
    val activeSlot: String = "_a",
    val kernelVersion: String = "Unknown",
    val userdataFs: String = "Unknown",
    val rootfsPresent: Boolean = false,
    val stockBackupReady: Boolean = false,
    val haliumImagesReady: Boolean = false,
    val backupDir: String = "/sdcard/.backup",
    val deviceModel: String = Build.MODEL,
    val deviceMarketName: String = "Redmi Note 14 4G",
    val deviceCodename: String = Build.DEVICE,
    val androidVersion: String = Build.VERSION.RELEASE,
    val osVersion: String = Build.DISPLAY
)

object RootShell {
    private val suCandidates = listOf(
        "/data/adb/ksu/bin/su",
        "/system/bin/su",
        "/system/xbin/su",
        "/sbin/su",
        "su"
    )

    suspend fun exec(script: String): Pair<Int, String> = withContext(Dispatchers.IO) {
        for (suBin in suCandidates) {
            try {
                val proc = ProcessBuilder(suBin, "-c", script)
                    .redirectErrorStream(true)
                    .start()
                val output = proc.inputStream.bufferedReader().readText().trim()
                val code = proc.waitFor()
                return@withContext code to output
            } catch (_: Exception) {
                // try next su candidate
            }
        }
        -1 to "Root (su) binary not found or permission denied"
    }

    suspend fun probeStatus(): SystemStatus {
        val probeScript = """
            SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
            if [ -z "${'$'}SLOT" ]; then
              SLOT=$(grep -o 'androidboot.slot_suffix=[^ ]*' /proc/cmdline | cut -d= -f2)
            fi
            [ -z "${'$'}SLOT" ] && SLOT="_a"
            KVER=$(uname -r 2>/dev/null || echo "unknown")
            FS=$(blkid /dev/block/by-name/userdata 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2)
            [ -z "${'$'}FS" ] && FS=$( awk '${'$'}2=="/data"{print ${'$'}3; exit}' /proc/mounts )
            ROOTFS=0
            [ -d /data/ubuntu/usr ] && ROOTFS=1
            BDIR="/sdcard/.backup"
            [ ! -d "${'$'}BDIR" ] && [ -d "/data/media/0/.backup" ] && BDIR="/data/media/0/.backup"
            STOCK_OK=0
            if [ -s "${'$'}BDIR/boot_stock.img" ] && [ -s "${'$'}BDIR/vendor_boot_stock.img" ] && [ -s "${'$'}BDIR/dtbo_stock.img" ]; then
              STOCK_OK=1
            fi
            HALIUM_OK=0
            if [ -s "${'$'}BDIR/boot_halium.img" ] && [ -s "${'$'}BDIR/vendor_boot_halium.img" ] && [ -s "${'$'}BDIR/dtbo_halium.img" ]; then
              HALIUM_OK=1
            elif [ -s "/data/ubuntu/partitions/boot.img" ] && [ -s "/data/ubuntu/partitions/vendor_boot.img" ]; then
              HALIUM_OK=1
            fi

            MARKET=$(getprop ro.product.marketname 2>/dev/null)
            [ -z "${'$'}MARKET" ] && MARKET=$(getprop ro.product.odm.marketname 2>/dev/null)
            [ -z "${'$'}MARKET" ] && MARKET="Redmi Note 14 4G"

            OSVER=$(getprop ro.mi.os.version.incremental 2>/dev/null)
            [ -z "${'$'}OSVER" ] && OSVER=$(getprop ro.build.version.incremental 2>/dev/null)
            [ -z "${'$'}OSVER" ] && OSVER=$(getprop ro.build.display.id 2>/dev/null)
            [ -z "${'$'}OSVER" ] && OSVER="HyperOS"

            DMODEL=$(getprop ro.product.model 2>/dev/null)
            [ -z "${'$'}DMODEL" ] && DMODEL="${Build.MODEL}"

            DDEVICE=$(getprop ro.product.device 2>/dev/null)
            [ -z "${'$'}DDEVICE" ] && DDEVICE="${Build.DEVICE}"

            AVER=$(getprop ro.build.version.release 2>/dev/null)
            [ -z "${'$'}AVER" ] && AVER="${Build.VERSION.RELEASE}"

            echo "SLOT=${'$'}SLOT"
            echo "KVER=${'$'}KVER"
            echo "FS=${'$'}FS"
            echo "ROOTFS=${'$'}ROOTFS"
            echo "STOCK_OK=${'$'}STOCK_OK"
            echo "HALIUM_OK=${'$'}HALIUM_OK"
            echo "BDIR=${'$'}BDIR"
            echo "MARKET=${'$'}MARKET"
            echo "OSVER=${'$'}OSVER"
            echo "DMODEL=${'$'}DMODEL"
            echo "DDEVICE=${'$'}DDEVICE"
            echo "AVER=${'$'}AVER"
        """.trimIndent()

        val (code, out) = exec(probeScript)
        if (code != 0) {
            return SystemStatus(hasRoot = false)
        }
        val map = out.lines().mapNotNull { line ->
            val idx = line.indexOf('=')
            if (idx > 0) line.substring(0, idx) to line.substring(idx + 1) else null
        }.toMap()

        return SystemStatus(
            hasRoot = true,
            activeSlot = map["SLOT"]?.ifBlank { "_a" } ?: "_a",
            kernelVersion = map["KVER"] ?: "Unknown",
            userdataFs = map["FS"] ?: "Unknown",
            rootfsPresent = map["ROOTFS"] == "1",
            stockBackupReady = map["STOCK_OK"] == "1",
            haliumImagesReady = map["HALIUM_OK"] == "1",
            backupDir = map["BDIR"] ?: "/sdcard/.backup",
            deviceModel = map["DMODEL"]?.ifBlank { Build.MODEL } ?: Build.MODEL,
            deviceMarketName = map["MARKET"]?.ifBlank { "Redmi Note 14 4G" } ?: "Redmi Note 14 4G",
            deviceCodename = map["DDEVICE"]?.ifBlank { Build.DEVICE } ?: Build.DEVICE,
            androidVersion = map["AVER"]?.ifBlank { Build.VERSION.RELEASE } ?: Build.VERSION.RELEASE,
            osVersion = map["OSVER"]?.ifBlank { Build.DISPLAY } ?: Build.DISPLAY
        )
    }

    suspend fun loadWallpaperBitmap(context: Context): Bitmap? = withContext(Dispatchers.IO) {
        val directCandidates = listOf(
            File("/data/system/theme_magic/users/0/wallpaper/image/home_wallpaper.jpg"),
            File("/data/system/theme_magic/users/0/wallpaper/image/lock_wallpaper.jpg"),
            File("/data/system/users/0/blurwallpaper")
        )
        val opts = BitmapFactory.Options().apply {
            inSampleSize = 2
        }

        // 1. Direct candidate files on HyperOS / MIUI
        for (f in directCandidates) {
            try {
                if (f.exists() && f.canRead() && f.length() > 0) {
                    val bmp = BitmapFactory.decodeFile(f.absolutePath, opts)
                    if (bmp != null) return@withContext bmp
                }
            } catch (_: Exception) {}
        }

        // 2. Standard AOSP WallpaperManager (for non-MIUI / vanilla Android)
        try {
            val wm = WallpaperManager.getInstance(context)
            val d = try {
                wm.drawable ?: wm.builtInDrawable
            } catch (_: SecurityException) {
                null
            }
            if (d != null) {
                if (d is BitmapDrawable) {
                    return@withContext d.bitmap
                }
                val w = d.intrinsicWidth.takeIf { it > 0 } ?: 400
                val h = d.intrinsicHeight.takeIf { it > 0 } ?: 400
                val bmp = Bitmap.createBitmap(w.coerceAtMost(800), h.coerceAtMost(800), Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bmp)
                d.setBounds(0, 0, canvas.width, canvas.height)
                d.draw(canvas)
                return@withContext bmp
            }
        } catch (_: Exception) {}

        // 3. Root extraction from protected system wallpaper locations (HyperOS / MIUI / live wallpapers)
        try {
            val cacheDir = context.cacheDir
            val targetFile = File(cacheDir, "current_wallpaper.img")
            val script = """
                TARGET="${targetFile.absolutePath}"
                for src in /data/system/theme_magic/users/0/wallpaper/image/home_wallpaper.jpg /data/system/users/0/wallpaper /data/system/users/0/wallpaper_orig /data/system/users/0/blurwallpaper /data/system_ce/0/wallpaper; do
                    if [ -s "${'$'}src" ]; then
                        cp "${'$'}src" "${'$'}TARGET"
                        chmod 644 "${'$'}TARGET"
                        exit 0
                    fi
                done
                exit 1
            """.trimIndent()
            val (code, _) = exec(script)
            if (code == 0 && targetFile.exists() && targetFile.length() > 0) {
                val bmp = BitmapFactory.decodeFile(targetFile.absolutePath, opts)
                if (bmp != null) {
                    return@withContext bmp
                }
            }
        } catch (_: Exception) {}

        null
    }
}

class MainActivity : ComponentActivity() {
    private val selectedTabState = mutableIntStateOf(0)
    private var floatingBarRef: LiquidGlassTabBar? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        window.statusBarColor = android.graphics.Color.TRANSPARENT

        val rootLayout = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        val composeView = ComposeView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setContent {
                val darkTheme = isSystemInDarkTheme()
                MiuixTheme(
                    colors = if (darkTheme) darkColorScheme() else lightColorScheme()
                ) {
                    MainAppScreen(
                        selectedTab = selectedTabState.intValue,
                        onTabChanged = { page ->
                            selectedTabState.intValue = page
                            floatingBarRef?.selectedIndex = page
                        },
                        onDialogVisibilityChanged = { isShowing ->
                            val bar = floatingBarRef ?: return@MainAppScreen
                            val density = resources.displayMetrics.density
                            bar.animate().cancel()
                            if (isShowing) {
                                bar.isEnabled = false
                                val transY = 220f * density
                                bar.animate()
                                    .translationY(transY)
                                    .alpha(0f)
                                    .setDuration(220)
                                    .withEndAction {
                                        if (bar.translationY > 50f * density) {
                                            bar.visibility = View.GONE
                                        }
                                    }
                                    .start()
                            } else {
                                bar.visibility = View.VISIBLE
                                bar.isEnabled = true
                                bar.animate()
                                    .translationY(0f)
                                    .alpha(1f)
                                    .setDuration(250)
                                    .start()
                            }
                        },
                        onScroll = {
                            floatingBarRef?.invalidate()
                        }
                    )
                }
            }
        }

        val density = resources.displayMetrics.density
        val floatingBarWidth = (260 * density).toInt()

        val floatingBar = LiquidGlassTabBar(this).apply {
            floatingBarRef = this
            layoutParams = FrameLayout.LayoutParams(
                floatingBarWidth,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).apply {
                bottomMargin = (20 * density).toInt()
            }
            enableBackdropBlur = true
            useHardwareBlurWhenPossible = true
            accessibilityMode = GlassAccessibilityMode.FORCE_FULL
            enableDynamicBackground = true
            enableAdaptiveTint = true
            enableEdgeHighlight = true
            edgeHighlightBorderWidth = 1f * density
            edgeHighlightOpacity = 28f
            blurAmount = 24f
            saturation = 125f
            material = GlassMaterial.CLEAR
            setGlassTint(0x00000000, 0.0f)
            cornerRadius = 999f
            selectedTintColor = 0xFF0A84FF.toInt()
            backdropSource = composeView

            val borderDrawable = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 999f * density
                setStroke((1 * density).toInt(), android.graphics.Color.argb(45, 255, 255, 255))
                setColor(android.graphics.Color.TRANSPARENT)
            }
            foreground = borderDrawable

            val switchDrawable = ContextCompat.getDrawable(context, R.drawable.ic_nav_switch)
            val infoDrawable = ContextCompat.getDrawable(context, R.drawable.ic_nav_info)

            setTabs(
                listOf(
                    LiquidGlassTabBar.TabItem("Switcher", switchDrawable),
                    LiquidGlassTabBar.TabItem("About", infoDrawable)
                )
            )

            this.selectedIndex = selectedTabState.intValue
            this.onTabSelected = { index ->
                selectedTabState.intValue = index
            }
        }

        ViewCompat.setOnApplyWindowInsetsListener(floatingBar) { v, insets ->
            val navInsets = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            val lp = v.layoutParams as? FrameLayout.LayoutParams
            if (lp != null) {
                lp.bottomMargin = (20 * density).toInt() + navInsets.bottom
                v.layoutParams = lp
            }
            insets
        }

        rootLayout.addView(composeView)
        rootLayout.addView(floatingBar)
        setContentView(rootLayout)
    }
}

@Composable
fun MainAppScreen(
    selectedTab: Int,
    onTabChanged: (Int) -> Unit,
    onDialogVisibilityChanged: (Boolean) -> Unit = {},
    onScroll: () -> Unit = {}
) {
    val scope = rememberCoroutineScope()
    val pagerState = rememberPagerState(initialPage = selectedTab) { 2 }

    val switcherScrollBehavior = MiuixScrollBehavior(rememberTopAppBarState())
    val aboutScrollBehavior = MiuixScrollBehavior(rememberTopAppBarState())

    val switcherListState = rememberLazyListState()
    val aboutListState = rememberLazyListState()

    // Sync tab changes from floating bar to pager with smooth spring animation
    LaunchedEffect(selectedTab) {
        if (pagerState.currentPage != selectedTab) {
            pagerState.animateScrollToPage(
                page = selectedTab,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioNoBouncy,
                    stiffness = Spring.StiffnessMediumLow
                )
            )
        }
    }

    // Sync pager swipe gestures back to floating bar
    LaunchedEffect(pagerState.currentPage) {
        if (selectedTab != pagerState.currentPage) {
            onTabChanged(pagerState.currentPage)
        }
    }

    // Continuously update floating liquid glass bar during scroll or page transition
    LaunchedEffect(switcherListState.firstVisibleItemScrollOffset, switcherListState.firstVisibleItemIndex) {
        onScroll()
    }
    LaunchedEffect(aboutListState.firstVisibleItemScrollOffset, aboutListState.firstVisibleItemIndex) {
        onScroll()
    }
    LaunchedEffect(pagerState.currentPageOffsetFraction) {
        onScroll()
    }

    var status by remember { mutableStateOf(SystemStatus()) }
    var isBusy by remember { mutableStateOf(false) }
    var consoleLog by remember { mutableStateOf("Ready. Tap an action below.") }
    val showConfirmUbuntu = remember { mutableStateOf(false) }
    val showConfirmAndroid = remember { mutableStateOf(false) }

    val isDialogShowing = showConfirmUbuntu.value || showConfirmAndroid.value
    LaunchedEffect(isDialogShowing) {
        onDialogVisibilityChanged(isDialogShowing)
    }

    fun appendLog(msg: String) {
        consoleLog = (consoleLog + "\n" + msg).trim()
    }

    fun refreshStatus() {
        scope.launch {
            status = RootShell.probeStatus()
        }
    }

    LaunchedEffect(Unit) {
        status = RootShell.probeStatus()
    }

    fun backupCurrentStock() {
        if (isBusy) return
        isBusy = true
        consoleLog = "[*] Backing up current slot (${status.activeSlot}) boot, vendor_boot, dtbo..."
        scope.launch {
            val script = """
                set -e
                SLOT="${status.activeSlot}"
                BDIR="/sdcard/.backup"
                mkdir -p "${'$'}BDIR"
                for p in boot vendor_boot dtbo; do
                  PART="/dev/block/by-name/${'$'}{p}${'$'}{SLOT}"
                  [ -e "${'$'}PART" ] || { echo "[!] Missing partition ${'$'}PART"; exit 1; }
                  dd if="${'$'}PART" of="${'$'}BDIR/${'$'}{p}_stock.img" bs=4M
                  [ -s "${'$'}BDIR/${'$'}{p}_stock.img" ] || { echo "[!] Backup failed for ${'$'}p"; exit 1; }
                  echo "[+] Saved ${'$'}BDIR/${'$'}{p}_stock.img"
                done
                sync
                echo "[+] Stock HyperOS boot backup complete!"
            """.trimIndent()
            val (code, out) = RootShell.exec(script)
            appendLog(out)
            if (code != 0) appendLog("[!] Backup exited with code $code")
            status = RootShell.probeStatus()
            isBusy = false
        }
    }

    fun switchToUbuntuTouch(rebootNow: Boolean) {
        if (isBusy) return
        isBusy = true
        consoleLog = "[*] Switching active slot (${status.activeSlot}) to Ubuntu Touch (Halium 12)..."
        scope.launch {
            val script = """
                set -e
                SLOT="${status.activeSlot}"
                BDIR="/sdcard/.backup"
                mkdir -p "${'$'}BDIR"
                # 1. Auto-backup stock if not yet backed up
                for p in boot vendor_boot dtbo; do
                  if [ ! -s "${'$'}BDIR/${'$'}{p}_stock.img" ]; then
                    echo "[*] Creating initial stock backup for ${'$'}{p}${'$'}{SLOT}..."
                    dd if="/dev/block/by-name/${'$'}{p}${'$'}{SLOT}" of="${'$'}BDIR/${'$'}{p}_stock.img" bs=4M
                  fi
                done

                # 2. Locate Halium images
                BOOT_IMG="${'$'}BDIR/boot_halium.img"
                VBOOT_IMG="${'$'}BDIR/vendor_boot_halium.img"
                DTBO_IMG="${'$'}BDIR/dtbo_halium.img"
                if [ ! -s "${'$'}BOOT_IMG" ] && [ -s "/data/ubuntu/partitions/boot.img" ]; then
                  BOOT_IMG="/data/ubuntu/partitions/boot.img"
                  VBOOT_IMG="/data/ubuntu/partitions/vendor_boot.img"
                  DTBO_IMG="/data/ubuntu/partitions/dtbo.img"
                fi

                for f in "${'$'}BOOT_IMG" "${'$'}VBOOT_IMG" "${'$'}DTBO_IMG"; do
                  [ -s "${'$'}f" ] || { echo "[!] Missing or empty Halium image: ${'$'}f"; exit 1; }
                done

                # 3. Validate target block devices & flash
                for p in boot vendor_boot dtbo; do
                  PART="/dev/block/by-name/${'$'}{p}${'$'}{SLOT}"
                  [ -e "${'$'}PART" ] || { echo "[!] Target partition ${'$'}PART not found!"; exit 1; }
                  blockdev --setrw "${'$'}PART" 2>/dev/null || true
                done

                dd if="${'$'}BOOT_IMG" of="/dev/block/by-name/boot${'$'}{SLOT}" bs=4M
                echo "[+] Flashed boot${'$'}{SLOT} <- ${'$'}BOOT_IMG"
                dd if="${'$'}VBOOT_IMG" of="/dev/block/by-name/vendor_boot${'$'}{SLOT}" bs=4M
                echo "[+] Flashed vendor_boot${'$'}{SLOT} <- ${'$'}VBOOT_IMG"
                dd if="${'$'}DTBO_IMG" of="/dev/block/by-name/dtbo${'$'}{SLOT}" bs=4M
                echo "[+] Flashed dtbo${'$'}{SLOT} <- ${'$'}DTBO_IMG"
                sync
                echo "[+] All Halium partitions flashed successfully!"
                if [ "${if (rebootNow) "1" else "0"}" = "1" ]; then
                  echo "[*] Rebooting into Ubuntu Touch..."
                  svc power reboot || reboot
                fi
            """.trimIndent()
            val (code, out) = RootShell.exec(script)
            appendLog(out)
            if (code != 0) appendLog("[!] Switch failed (exit $code)")
            status = RootShell.probeStatus()
            isBusy = false
        }
    }

    fun restoreStockAndroid(rebootNow: Boolean) {
        if (isBusy) return
        isBusy = true
        consoleLog = "[*] Restoring Stock HyperOS images to slot ${status.activeSlot}..."
        scope.launch {
            val script = """
                set -e
                SLOT="${status.activeSlot}"
                BDIR="/sdcard/.backup"
                for p in boot vendor_boot dtbo; do
                  IMG="${'$'}BDIR/${'$'}{p}_stock.img"
                  PART="/dev/block/by-name/${'$'}{p}${'$'}{SLOT}"
                  [ -s "${'$'}IMG" ] || { echo "[!] Backup image ${'$'}IMG missing or empty!"; exit 1; }
                  [ -e "${'$'}PART" ] || { echo "[!] Target partition ${'$'}PART missing!"; exit 1; }
                  blockdev --setrw "${'$'}PART" 2>/dev/null || true
                  dd if="${'$'}IMG" of="${'$'}PART" bs=4M
                  echo "[+] Restored ${'$'}{p}${'$'}{SLOT} <- ${'$'}IMG"
                done
                sync
                echo "[+] Stock HyperOS boot partitions restored!"
                if [ "${if (rebootNow) "1" else "0"}" = "1" ]; then
                  echo "[*] Rebooting into Android (HyperOS)..."
                  svc power reboot || reboot
                fi
            """.trimIndent()
            val (code, out) = RootShell.exec(script)
            appendLog(out)
            if (code != 0) appendLog("[!] Restore failed (exit $code)")
            status = RootShell.probeStatus()
            isBusy = false
        }
    }

    @OptIn(ExperimentalFoundationApi::class)
    CompositionLocalProvider(
        LocalOverscrollFactory provides null,
        @Suppress("DEPRECATION")
        LocalOverscrollConfiguration provides null
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize()
        ) { page ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clipToBounds()
                    .background(MiuixTheme.colorScheme.background)
            ) {
                if (page == 0) {
                    Scaffold(
                        modifier = Modifier.fillMaxSize(),
                        containerColor = Color.Transparent,
                        topBar = {
                            TopAppBar(
                                title = "Tanzanite OS Switcher",
                                largeTitle = "Tanzanite Dual-Boot",
                                scrollBehavior = switcherScrollBehavior,
                                color = Color.Transparent,
                                modifier = Modifier.background(
                                    Brush.verticalGradient(
                                        colors = listOf(
                                            Color.Black.copy(alpha = 0.85f),
                                            Color.Black.copy(alpha = 0.50f),
                                            Color.Transparent
                                        )
                                    )
                                )
                            )
                        }
                    ) { innerPadding ->
                        SwitcherContent(
                            modifier = Modifier
                                .fillMaxSize()
                                .nestedScroll(switcherScrollBehavior.nestedScrollConnection),
                            listState = switcherListState,
                            innerPadding = innerPadding,
                            status = status,
                            isBusy = isBusy,
                            consoleLog = consoleLog,
                            onRefresh = { refreshStatus() },
                            onBackupStock = { backupCurrentStock() },
                            onRequestUbuntu = { showConfirmUbuntu.value = true },
                            onRequestRestore = { showConfirmAndroid.value = true }
                        )
                    }
                } else {
                    Scaffold(
                        modifier = Modifier.fillMaxSize(),
                        containerColor = Color.Transparent,
                        topBar = {
                            TopAppBar(
                                title = "About",
                                largeTitle = "About",
                                scrollBehavior = aboutScrollBehavior,
                                color = Color.Transparent,
                                modifier = Modifier.background(
                                    Brush.verticalGradient(
                                        colors = listOf(
                                            Color.Black.copy(alpha = 0.85f),
                                            Color.Black.copy(alpha = 0.50f),
                                            Color.Transparent
                                        )
                                    )
                                )
                            )
                        }
                    ) { innerPadding ->
                        AboutContent(
                            modifier = Modifier
                                .fillMaxSize()
                                .nestedScroll(aboutScrollBehavior.nestedScrollConnection),
                            listState = aboutListState,
                            innerPadding = innerPadding,
                            status = status
                        )
                    }
                }

                // Frosted gradient scrim overlay behind status bar & header
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .windowInsetsTopHeight(WindowInsets.statusBars)
                        .background(Color.Black.copy(alpha = 0.65f))
                )
            }
        }
    }

    SuperDialog(
        title = "Boot to Ubuntu Touch?",
        summary = "This will flash Halium boot, vendor_boot, and dtbo to active slot (${status.activeSlot}) and immediately reboot the device.",
        show = showConfirmUbuntu,
        onDismissRequest = { MiuixPopupUtils.dismissDialog(showConfirmUbuntu) }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                TextButton(
                    text = "Cancel",
                    onClick = { MiuixPopupUtils.dismissDialog(showConfirmUbuntu) },
                    modifier = Modifier.weight(1f)
                )
                TextButton(
                    text = "Flash & Reboot",
                    onClick = {
                        MiuixPopupUtils.dismissDialog(showConfirmUbuntu)
                        switchToUbuntuTouch(rebootNow = true)
                    },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.textButtonColorsPrimary()
                )
            }
        }
    }

    SuperDialog(
        title = "Restore Stock HyperOS?",
        summary = "This will flash boot_stock.img, vendor_boot_stock.img, and dtbo_stock.img from /sdcard/.backup/ back to slot ${status.activeSlot}.",
        show = showConfirmAndroid,
        onDismissRequest = { MiuixPopupUtils.dismissDialog(showConfirmAndroid) }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                TextButton(
                    text = "Cancel",
                    onClick = { MiuixPopupUtils.dismissDialog(showConfirmAndroid) },
                    modifier = Modifier.weight(1f)
                )
                TextButton(
                    text = "Restore Only",
                    onClick = {
                        MiuixPopupUtils.dismissDialog(showConfirmAndroid)
                        restoreStockAndroid(rebootNow = false)
                    },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.textButtonColorsPrimary()
                )
            }
        }
    }
}

@Composable
fun SwitcherContent(
    modifier: Modifier = Modifier,
    listState: LazyListState,
    innerPadding: PaddingValues,
    status: SystemStatus,
    isBusy: Boolean,
    consoleLog: String,
    onRefresh: () -> Unit,
    onBackupStock: () -> Unit,
    onRequestUbuntu: () -> Unit,
    onRequestRestore: () -> Unit
) {
    val layoutDirection = LocalLayoutDirection.current
    val statusBarTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val topBarPadding = innerPadding.calculateTopPadding()
    val topPadding = if (topBarPadding > statusBarTop) topBarPadding else (statusBarTop + 56.dp)

    LazyColumn(
        state = listState,
        modifier = modifier.overScrollVertical(),
        contentPadding = PaddingValues(
            top = topPadding + 8.dp,
            bottom = 140.dp,
            start = innerPadding.calculateStartPadding(layoutDirection),
            end = innerPadding.calculateEndPadding(layoutDirection)
        )
    ) {
        item {
            SmallTitle(text = "DEVICE & PARTITION STATUS")
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                SuperArrow(
                    title = "Root Access (KernelSU / su)",
                    summary = if (status.hasRoot) "Granted (uid=0)" else "Not detected - grant root in KernelSU",
                    rightText = if (status.hasRoot) "Active" else "Denied",
                    onClick = { onRefresh() }
                )
                SuperArrow(
                    title = "Active A/B Slot",
                    summary = "Slot B (_b) is preserved untouched as fallback",
                    rightText = status.activeSlot,
                    onClick = { onRefresh() }
                )
                SuperArrow(
                    title = "Userdata Filesystem (/data)",
                    summary = "Kernel: ${status.kernelVersion}",
                    rightText = status.userdataFs,
                    onClick = { onRefresh() }
                )
                SuperArrow(
                    title = "Ubuntu Touch Rootfs (/data/ubuntu)",
                    summary = if (status.rootfsPresent) "Installed & verified" else "Not found in /data/ubuntu",
                    rightText = if (status.rootfsPresent) "Ready" else "Missing",
                    onClick = { onRefresh() }
                )
                SuperArrow(
                    title = "Boot Image Backups (/sdcard/.backup)",
                    summary = "Stock: ${if (status.stockBackupReady) "OK" else "Missing"} | Halium: ${if (status.haliumImagesReady) "OK" else "Missing"}",
                    rightText = if (status.stockBackupReady && status.haliumImagesReady) "Ready" else "Check",
                    onClick = { onRefresh() }
                )
            }
        }

        item {
            Spacer(modifier = Modifier.height(8.dp))
            SmallTitle(text = "ONE-TAP OS SWITCHING")
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                insideMargin = PaddingValues(16.dp)
            ) {
                Text(
                    text = "Boot to Ubuntu Touch 20.04",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Automatically backs up Stock HyperOS partitions if needed, flashes Halium boot, vendor_boot, and dtbo to active slot (${status.activeSlot}), and reboots into Ubuntu Touch.",
                    fontSize = 13.sp,
                    color = Color.Gray
                )
                Spacer(modifier = Modifier.height(12.dp))
                TextButton(
                    text = if (isBusy) "Working..." else "Switch to Ubuntu Touch & Reboot",
                    onClick = onRequestUbuntu,
                    enabled = !isBusy && status.hasRoot,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.textButtonColorsPrimary()
                )
            }

            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                insideMargin = PaddingValues(16.dp)
            ) {
                Text(
                    text = "Backup / Restore Stock HyperOS",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Save current Android boot/vendor_boot/dtbo to /sdcard/.backup/ or restore them to slot ${status.activeSlot}.",
                    fontSize = 13.sp,
                    color = Color.Gray
                )
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    TextButton(
                        text = "Backup Stock Now",
                        onClick = onBackupStock,
                        enabled = !isBusy && status.hasRoot,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(
                        text = "Restore Stock",
                        onClick = onRequestRestore,
                        enabled = !isBusy && status.hasRoot && status.stockBackupReady,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        item {
            Spacer(modifier = Modifier.height(8.dp))
            SmallTitle(text = "EXECUTION LOG")
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                insideMargin = PaddingValues(14.dp)
            ) {
                Text(
                    text = consoleLog,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

@Composable
fun AboutContent(
    modifier: Modifier = Modifier,
    listState: LazyListState,
    innerPadding: PaddingValues,
    status: SystemStatus
) {
    val context = LocalContext.current
    val openUrl: (String) -> Unit = { url ->
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            context.startActivity(intent)
        } catch (_: Exception) {}
    }

    val layoutDirection = LocalLayoutDirection.current
    val statusBarTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val topBarPadding = innerPadding.calculateTopPadding()
    val topPadding = if (topBarPadding > statusBarTop) topBarPadding else (statusBarTop + 56.dp)

    val wallpaperBitmap by produceState<Bitmap?>(initialValue = null) {
        value = RootShell.loadWallpaperBitmap(context)
    }

    LazyColumn(
        state = listState,
        modifier = modifier.overScrollVertical(),
        contentPadding = PaddingValues(
            top = topPadding + 8.dp,
            bottom = 140.dp,
            start = innerPadding.calculateStartPadding(layoutDirection),
            end = innerPadding.calculateEndPadding(layoutDirection)
        )
    ) {
        // Hero Card with Wallpaper Background + Blur + Scrim
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                insideMargin = PaddingValues(0.dp)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    val currentWp = wallpaperBitmap
                    if (currentWp != null) {
                        Image(
                            bitmap = currentWp.asImageBitmap(),
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .matchParentSize()
                                .then(
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                        Modifier.blur(radius = 10.dp)
                                    } else {
                                        Modifier
                                    }
                                )
                        )
                        // Dark scrim overlay for high contrast text readability
                        Box(
                            modifier = Modifier
                                .matchParentSize()
                                .background(
                                    Brush.verticalGradient(
                                        listOf(
                                            Color.Black.copy(alpha = 0.20f),
                                            Color.Black.copy(alpha = 0.50f)
                                        )
                                    )
                                )
                        )
                    } else {
                        // Gradient fallback if wallpaper is unavailable
                        Box(
                            modifier = Modifier
                                .matchParentSize()
                                .background(
                                    Brush.verticalGradient(
                                        listOf(
                                            Color(0xFF1E2638),
                                            Color(0xFF0F141E)
                                        )
                                    )
                                )
                        )
                    }

                    // Hero content: app icon, app title, and version
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 24.dp, horizontal = 16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Box(
                            modifier = Modifier
                                .size(80.dp)
                                .shadow(elevation = 6.dp, shape = CircleShape)
                                .clip(CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Image(
                                painter = painterResource(R.drawable.icon_app),
                                contentDescription = "App Icon",
                                modifier = Modifier.size(80.dp)
                            )
                        }

                        Spacer(modifier = Modifier.height(12.dp))

                        Text(
                            text = "Tanzanite Switcher",
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )

                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = "1.0.0 | Halium 12 Dual-Boot",
                            fontSize = 13.sp,
                            color = Color.White.copy(alpha = 0.82f)
                        )
                    }
                }
            }
        }

        // Device Info Card matching Screenshot 1
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                insideMargin = PaddingValues(18.dp)
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = status.deviceMarketName,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(bottom = 14.dp)
                    )

                    Column(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = "${status.deviceModel} (${status.deviceCodename})",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "Device",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                    }

                    Spacer(modifier = Modifier.height(14.dp))

                    Column(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = status.androidVersion,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "Android version",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                    }

                    Spacer(modifier = Modifier.height(14.dp))

                    Column(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = status.osVersion,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "OS version",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                    }
                }
            }
        }

        // Developer Profile Card matching Screenshot 2
        item {
            Spacer(modifier = Modifier.height(6.dp))
            SmallTitle(text = "DEVELOPER")
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                SuperArrow(
                    leftAction = {
                        Box(
                            modifier = Modifier
                                .padding(end = 16.dp)
                                .size(26.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                painter = painterResource(R.drawable.ic_github),
                                contentDescription = "GitHub",
                                modifier = Modifier.size(22.dp),
                                tint = MiuixTheme.colorScheme.onSurface
                            )
                        }
                    },
                    title = "iprjkt | Tanzanite",
                    summary = "Port maintainer & kernel developer",
                    rightText = "@iprjkt",
                    onClick = { openUrl("https://github.com/iprjkt") }
                )
                SuperArrow(
                    leftAction = {
                        Box(
                            modifier = Modifier
                                .padding(end = 16.dp)
                                .size(26.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                painter = painterResource(R.drawable.ic_telegram),
                                contentDescription = "Telegram",
                                modifier = Modifier.size(22.dp),
                                tint = Color(0xFF2AABEE)
                            )
                        }
                    },
                    title = "Telegram",
                    summary = "Personal contact & developer account",
                    rightText = "@anotherside551",
                    onClick = { openUrl("https://t.me/anotherside551") }
                )
            }
        }

        // Community & Support Links
        item {
            Spacer(modifier = Modifier.height(6.dp))
            SmallTitle(text = "COMMUNITY & SUPPORT")
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                SuperArrow(
                    leftAction = {
                        Box(
                            modifier = Modifier
                                .padding(end = 16.dp)
                                .size(26.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                painter = painterResource(R.drawable.ic_telegram),
                                contentDescription = "Telegram Support Group",
                                modifier = Modifier.size(22.dp),
                                tint = Color(0xFF2AABEE)
                            )
                        }
                    },
                    title = "Telegram Support Group",
                    summary = "Community discussion & troubleshooting group",
                    rightText = "@idiscuss1",
                    onClick = { openUrl("https://t.me/idiscuss1") }
                )
                SuperArrow(
                    leftAction = {
                        Box(
                            modifier = Modifier
                                .padding(end = 16.dp)
                                .size(26.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Image(
                                painter = painterResource(R.drawable.icon_app),
                                contentDescription = null,
                                modifier = Modifier
                                    .size(22.dp)
                                    .clip(CircleShape)
                            )
                        }
                    },
                    title = "UBports Documentation",
                    summary = "Official Halium & Ubuntu Touch guides",
                    rightText = "ubports.com",
                    onClick = { openUrl("https://docs.ubports.com") }
                )
            }
        }

        // Donation & Sponsor matching HyperCeiler
        item {
            Spacer(modifier = Modifier.height(6.dp))
            SmallTitle(text = "DONATION & SPONSOR")
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                SuperArrow(
                    leftAction = {
                        Box(
                            modifier = Modifier
                                .padding(end = 16.dp)
                                .size(26.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = MiuixIcons.Useful.Like,
                                contentDescription = "Donate",
                                modifier = Modifier.size(22.dp),
                                tint = Color(0xFFE95420)
                            )
                        }
                    },
                    title = "Donate / Sponsor",
                    summary = "Support Tanzanite port maintenance via Sociabuzz",
                    rightText = "Sociabuzz",
                    onClick = { openUrl("https://sociabuzz.com/fxxyz73/tribe") }
                )
            }
        }

        // Port Architecture & Device Specs
        item {
            Spacer(modifier = Modifier.height(6.dp))
            SmallTitle(text = "PORT SPECIFICATIONS")
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                SuperArrow(
                    title = "Platform",
                    summary = "MediaTek Helio G99 Ultra (MT6789)",
                    rightText = "arm64-v8a",
                    onClick = {}
                )
                SuperArrow(
                    title = "Base OS",
                    summary = "Ubuntu Touch Focal 20.04 (Halium 12)",
                    rightText = if (status.rootfsPresent) "Installed" else "Missing",
                    onClick = {}
                )
                SuperArrow(
                    title = "Dual-Boot Target",
                    summary = "Separate boot/dtbo/rootfs partitions on Slot A",
                    rightText = status.activeSlot,
                    onClick = {}
                )
                SuperArrow(
                    title = "Linux Kernel",
                    summary = "KernelSU enabled GKI build",
                    rightText = status.kernelVersion,
                    onClick = {}
                )
            }
        }
    }
}

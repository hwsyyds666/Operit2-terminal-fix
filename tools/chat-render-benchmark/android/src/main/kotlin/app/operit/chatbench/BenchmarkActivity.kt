package app.operit.chatbench

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.FrameMetrics
import android.view.Window
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.ceil

class BenchmarkActivity : ComponentActivity() {
    private val frames = mutableListOf<Double>()
    private var recording = false
    private val listener = Window.OnFrameMetricsAvailableListener { _, metrics, _ ->
        if (recording) {
            frames.add(metrics.getMetric(FrameMetrics.TOTAL_DURATION) / 1_000_000.0)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addOnFrameMetricsAvailableListener(listener, Handler(Looper.getMainLooper()))
        val messages = List(1000) { "Message $it: 中文 Markdown and tool history" }
        val cells = List(40) { row -> List(4) { "$row / $it" } }
        val output = List(24) { "Output line $it" }.joinToString("\n")
        val live = List(49) { " live".repeat(it) }
        val style = TextStyle(fontSize = 14.sp)
        setContent {
            val list = rememberLazyListState()
            var toolOpen by remember { mutableStateOf(false) }
            var tokens by remember { mutableIntStateOf(0) }
            LaunchedEffect(Unit) {
                delay(500)
                recording = true
                repeat(5) {
                    list.animateScrollBy(
                        1600f * resources.displayMetrics.density,
                        tween(220, easing = LinearEasing),
                    )
                }
                list.scrollToItem(0)
                toolOpen = true
                repeat(48) {
                    tokens = it + 1
                    delay(32)
                }
                toolOpen = false
                delay(300)
                recording = false
                val sorted = frames.sorted()
                if (sorted.isNotEmpty()) {
                    val p95 = sorted[ceil(sorted.size * .95).toInt() - 1]
                    Log.i("ChatRenderBenchmark", "compose frames="+sorted.size+" totalP95Ms="+p95)
                }
            }
            LazyColumn(state = list, reverseLayout = true, modifier = Modifier.fillMaxSize()) {
                items(messages.size, key = { it }) { i ->
                    Column(Modifier.fillMaxWidth().padding(8.dp)) {
                        BasicText(messages[i] + if (i == 0) live[tokens] else "", style = style)
                        if (i % 20 == 0) {
                            for (row in cells) Row(Modifier.fillMaxWidth()) {
                                for (cell in row) BasicText(cell, Modifier.weight(1f), style)
                            }
                        }
                        if (i % 5 == 0) {
                            var expanded by remember { mutableStateOf(false) }
                            BasicText("Tool result", Modifier.clickable { expanded = !expanded }, style)
                            if ((i == 0 && toolOpen) || expanded) BasicText(output, style = style)
                        }
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        window.removeOnFrameMetricsAvailableListener(listener)
        super.onDestroy()
    }
}

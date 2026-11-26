package app.operit

import java.io.InputStream

/** Searches one document in a single pass, retaining only recent lines and matching previews. */
internal object DocumentTextSearch {
    private const val MAX_LINE_CHARS = 1024 * 1024
    private const val PREVIEW_CHARS = 512

    data class Hit(val lineNumber: Int, val line: String, val context: List<String>)
    data class Result(val hits: List<Hit>, val skippedLongLines: Int)

    fun scan(input: InputStream, pattern: Regex, contextLines: Int, maximum: Int): Result {
        if (maximum <= 0) return Result(emptyList(), 0)
        val previous = ArrayDeque<String>()
        val pending = ArrayDeque<Pair<Int, MutableList<String>>>()
        val hits = mutableListOf<Hit>()
        val line = StringBuilder()
        var number = 0
        var skipped = 0
        var tooLong = false
        var afterCarriageReturn = false

        fun consumeLine(): Boolean {
            number++
            if (tooLong) skipped++
            val content = if (tooLong) "" else line.toString()
            val match = if (!tooLong && hits.size < maximum) pattern.find(content) else null
            val preview = if (tooLong) "[Line too long for content search]" else preview(content, match?.range?.first ?: 0)
            while (pending.isNotEmpty() && number - pending.first().first > contextLines) {
                pending.removeFirst()
            }
            val numbered = "$number: $preview"
            for ((_, context) in pending) context.add(numbered)
            if (match != null) {
                val context = if (contextLines == 0) mutableListOf() else previous.toMutableList()
                if (contextLines > 0) {
                    context.add(numbered)
                    pending.addLast(number to context)
                }
                hits.add(Hit(number, preview, context))
            }
            if (contextLines > 0) {
                if (previous.size == contextLines) previous.removeFirst()
                previous.addLast(numbered)
            }
            line.setLength(0)
            tooLong = false
            return hits.size == maximum && number - hits.last().lineNumber >= contextLines
        }

        val reader = input.reader(Charsets.UTF_8)
        val buffer = CharArray(16 * 1024)
        while (true) {
            val count = reader.read(buffer)
            if (count < 0) break
            for (index in 0 until count) {
                val char = buffer[index]
                if (char == '\u0000') return Result(emptyList(), 0)
                if (char == '\n' && afterCarriageReturn) {
                    afterCarriageReturn = false
                    continue
                }
                afterCarriageReturn = char == '\r'
                if (char == '\n' || char == '\r') {
                    if (consumeLine()) return Result(hits, skipped)
                } else if (line.length < MAX_LINE_CHARS) {
                    line.append(char)
                } else {
                    tooLong = true
                }
            }
        }
        if (line.isNotEmpty() || tooLong) consumeLine()
        return Result(hits, skipped)
    }

    private fun preview(line: String, matchIndex: Int): String {
        if (line.length <= PREVIEW_CHARS) return line
        var start = (matchIndex - PREVIEW_CHARS / 3).coerceIn(0, line.length - PREVIEW_CHARS)
        if (Character.isLowSurrogate(line[start])) start--
        var end = start + PREVIEW_CHARS
        if (Character.isHighSurrogate(line[end - 1])) end--
        return (if (start > 0) "…" else "") + line.substring(start, end) + (if (end < line.length) "…" else "")
    }
}

package app.operit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.SequenceInputStream
import java.util.Collections

class DocumentTextSearchTest {
    @Test
    fun searchesPastEightMiBWithAccurateContext() {
        val page = ("neutral " + "x".repeat(246) + "\n").repeat(1024).toByteArray()
        val fillerPages = List(36) { page.inputStream() }
        val tail = "上下文\r\nmatch 中文\r\nafter".byteInputStream()
        val input = SequenceInputStream(Collections.enumeration(fillerPages + tail))
        val result = input.use { DocumentTextSearch.scan(it, Regex("match"), 1, 1) }
        val hit = result.hits.single()
        assertEquals(36 * 1024 + 2, hit.lineNumber)
        assertEquals("match 中文", hit.line)
        assertEquals(listOf(
            "${hit.lineNumber - 1}: 上下文", "${hit.lineNumber}: match 中文",
            "${hit.lineNumber + 1}: after",
        ), hit.context)
        assertEquals(0, result.skippedLongLines)
    }

    @Test
    fun skipsAnOversizedLineAndKeepsSearching() {
        val input = ("x".repeat(1024 * 1024 + 1) + "\nmatch here\nmatch again").byteInputStream()
        val result = input.use { DocumentTextSearch.scan(it, Regex("match"), 1, 1) }
        assertEquals(1, result.skippedLongLines)
        assertEquals(2, result.hits.single().lineNumber)
        assertTrue(result.hits.single().context.first().contains("Line too long"))
    }

    @Test
    fun returnsOnlyTheRequestedMatchesAndRejectsBinaryInput() {
        val text = "match first\nmatch second\nmatch third"
        val result = text.byteInputStream().use { DocumentTextSearch.scan(it, Regex("match"), 0, 2) }
        assertEquals(listOf(1, 2), result.hits.map { it.lineNumber })
        val binary = "match\u0000binary".byteInputStream()
        assertTrue(binary.use { DocumentTextSearch.scan(it, Regex("match"), 0, 10) }.hits.isEmpty())
    }
}

package com.printer.printer_label

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class PrintDirtyStoreTest {
    @Before
    fun reset() = PrintDirtyStore.resetForTest()

    @Test
    fun markThenClear() {
        assertFalse(PrintDirtyStore.isDirty("192.168.1.10:9100"))
        PrintDirtyStore.mark("192.168.1.10:9100")
        assertTrue(PrintDirtyStore.isDirty("192.168.1.10:9100"))
        assertFalse(PrintDirtyStore.isDirty("192.168.1.11:9100"))
        PrintDirtyStore.clear("192.168.1.10:9100")
        assertFalse(PrintDirtyStore.isDirty("192.168.1.10:9100"))
    }

    @Test
    fun blankOrNullKeyIsIgnored() {
        PrintDirtyStore.mark(null)
        PrintDirtyStore.mark("")
        PrintDirtyStore.mark("  ")
        assertFalse(PrintDirtyStore.isDirty(null))
        assertFalse(PrintDirtyStore.isDirty(""))
        PrintDirtyStore.clear(null)
    }

    @Test
    fun flushCoversLargestRasterStrip() {
        val b = PrintDirtyStore.FLUSH_BYTES
        // Một dải GS v 0: tối đa 128 dòng x 128 byte/dòng.
        assertTrue(b.size - 2 >= 128 * 128)
        // Toàn 0x00 rồi ESC @.
        assertTrue(b.take(PrintDirtyStore.FLUSH_ZEROS).all { it == 0.toByte() })
        assertEquals(0x1B.toByte(), b[b.size - 2])
        assertEquals(0x40.toByte(), b[b.size - 1])
    }
}

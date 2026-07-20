import java.lang.reflect.Modifier

fun main() {
    try {
        val clazz = Class.forName("android.device.PrinterManager")
        val fields = clazz.declaredFields
        for (f in fields) {
            if (Modifier.isStatic(f.modifiers)) {
                println("${f.name} = ${f.get(null)}")
            }
        }
    } catch(e: Exception) {
        println(e)
    }
}

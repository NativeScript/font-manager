package org.nativescript.fontmanager

object FontParser {
	private val TOKEN_REGEX = Regex("""'[^']*'|"[^"]*"|[^,\s]+|,""")

	data class Result(
		val style: FontStyle = FontStyle.Normal,
		val weight: FontWeight = FontWeight.Normal,
		val sizePx: Int,
		val lineHeight: Float? = null,
		val families: List<String>
	) {
		/** Lowercased [families], computed once because Results are memoized. */
		internal val familyKeys: List<String> by lazy { families.map { it.lowercase() } }
	}

	/** Sentinel so inputs that fail to parse are cached too, instead of re-tokenizing every call. */
	private val PARSE_FAILED = Any()
	private val cache = LruMap<String, Any>(64)

	/**
	 * [Result] is immutable, so parses of the same shorthand are memoized —
	 * `check`/`load` are called per draw and were re-running the tokenizer each time.
	 */
	fun parse(input: String): Result? {
		cache[input]?.let {
			return if (it === PARSE_FAILED) null else it as Result
		}
		val result = parseUncached(input)
		cache[input] = result ?: PARSE_FAILED
		return result
	}

	private fun parseUncached(input: String): Result? {
		val tokens = tokenize(input)

		var style: FontStyle = FontStyle.Normal
		var weight = FontWeight.Normal
		var size: Int? = null
		var lineHeight: Float? = null

		val families = mutableListOf<String>()
		val familyBuffer = StringBuilder()

		var i = 0
		var readingFamilies = false

		while (i < tokens.size) {
			val t = tokens[i]

			// next family
			if (t == ",") {
				flushFamily(familyBuffer, families)
				i++
				continue
			}

			when {
				t == "italic" -> style = FontStyle.Italic

				t.startsWith("oblique") -> {
					val angle = t.removePrefix("oblique").trim().toIntOrNull() ?: 0
					style = FontStyle.Oblique(angle)
				}

				t == "bold" -> weight = FontWeight.Bold

				t.toIntOrNull() != null && t.toInt() in 100..900 -> {
					weight = FontWeight.from(t.toInt())
				}

				// Matched on the part before the slash so the `<size>/<line-height>`
				// shorthand reaches the split below; `endsWith("px")` saw "16px/1.5"
				// as a family name and left size null, failing the whole parse.
				t.substringBefore("/").endsWith("px") -> {
					val parts = t.split("/")

					size = parts[0].removeSuffix("px").toIntOrNull()

					if (parts.size > 1) {
						lineHeight = parts[1].toFloatOrNull()
					}

					readingFamilies = true
				}

				readingFamilies -> {
					if (familyBuffer.isNotEmpty()) familyBuffer.append(" ")
					familyBuffer.append(t.trim('"', '\''))
				}
			}

			i++
		}

		flushFamily(familyBuffer, families)

		val finalSize = size ?: return null

		return Result(
			style = style,
			weight = weight,
			sizePx = finalSize,
			lineHeight = lineHeight,
			// Copied because the Result is shared out of the parse cache.
			families = families.toList()
		)
	}

	private fun tokenize(input: String): List<String> {
		return TOKEN_REGEX.findAll(input).map { it.value }.toList()
	}

	private fun flushFamily(buffer: StringBuilder, out: MutableList<String>) {
		if (buffer.isNotEmpty()) {
			out.add(buffer.toString().trim())
			buffer.clear()
		}
	}
}

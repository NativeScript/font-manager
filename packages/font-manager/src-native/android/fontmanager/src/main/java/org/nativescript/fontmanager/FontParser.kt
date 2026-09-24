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
				// shorthand reaches the split below.
				!readingFamilies && sizeInPx(t.substringBefore("/")) != null -> {
					val parts = t.split("/")

					size = sizeInPx(parts[0])

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

	private val LENGTH_REGEX = Regex("""^(\d*\.?\d+)(px|pt|em|rem|%)$""")

	private val SIZE_KEYWORDS = mapOf(
		"xx-small" to 9, "x-small" to 10, "small" to 13, "medium" to 16,
		"large" to 18, "x-large" to 24, "xx-large" to 32, "xxx-large" to 48,
	)

	/** Relative units resolve against the 16px default, since there is no parent element to inherit from. */
	private fun sizeInPx(token: String): Int? {
		SIZE_KEYWORDS[token]?.let { return it }
		val (value, unit) = LENGTH_REGEX.find(token)?.destructured ?: return null
		val px = when (unit) {
			"pt" -> value.toFloat() * 4 / 3
			"em", "rem" -> value.toFloat() * 16
			"%" -> value.toFloat() * 0.16f
			else -> value.toFloat()
		}
		return Math.round(px)
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

package scripture.viewer.skip.ui

import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import scripture.text.*
import skip.lib.Array
import skip.ui.ComposeContext

@RunWith(AndroidJUnit4::class)
class WrapperCheck {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun find(view: View, name: String): View? {
        if (view.javaClass.simpleName == name) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i), name)?.let { return it }
        return null
    }

    @Test
    fun theSwiftUIViewShowsTheComposeViewer() {
        val text = "1In the beginning God created.\n2And the earth was without form.\n" + "3More text here.\n".repeat(120)
        val verses = Array(listOf(ScriptureText.VerseRange(verse = 1, start = 0, length = 31), ScriptureText.VerseRange(verse = 2, start = 32, length = 34)))
        val spans = Array(listOf(ScriptureText.Span(0, 1, ScriptureText.Attribute.verseNumber(1)), ScriptureText.Span(32, 1, ScriptureText.Attribute.verseNumber(2))))
        val model = ScriptureText(text = text, spans = spans, verses = verses)
        val controller = ScriptureViewerController()
        val events = ScriptureViewerEvents()
        var tapped: TapTarget? = null
        events.onTap = { tapped = it }
        val wrapper = ScriptureViewer(text = model, controller = controller, events = events)
        compose.setContent { wrapper.Compose(ComposeContext()) }
        compose.waitForIdle()
        val view = compose.runOnUiThread<View?> { find(compose.activity.window.decorView, "ScriptureTextView") }
        assertNotNull("the viewer's view is on screen", view)
        val shown = compose.runOnUiThread<String> { find(view!!, "ReaderTextView")!!.let { (it as android.widget.TextView).text.toString() } }
        assertEquals(text, shown)
        assertTrue("the controller drives the view", controller.driver != null)
        controller.scroll(toVerse = 2)
        compose.waitForIdle()
        assertEquals(2, controller.currentVerse)
    }
}

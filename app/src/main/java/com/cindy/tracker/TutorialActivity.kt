package com.cindy.tracker

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityTutorialBinding
import kotlin.math.abs

/**
 * Five pages that show a new athlete around before the camera opens.
 *
 * They come before the camera's permission prompt rather than after it, for the reason a prompt
 * with no context gets refused: by the time Android asks to use the camera, the athlete has just
 * been told what this app is, that the picture never leaves the phone, and why it wants to see
 * them. The pages are built in code from the same pieces as [HelpActivity], so a large font
 * scrolls instead of clipping.
 *
 * The second page is the one that matters most and is the only one with a control of its own.
 * Cindy is easy to read as a strict workout that an athlete who is not there yet cannot do, and
 * an app that counts nothing for them is an app that looks broken. So it says, before anything
 * else, that other movements count, which ones, and how to choose them.
 *
 * The same pages are taken again from Help. [EXTRA_REPLAY] is what tells the two apart: the first
 * time they end at the camera's permission prompt, and on a replay they go back to the camera
 * screen, closing the menu and the help above it.
 */
class TutorialActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_REPLAY = "replay"
        private const val STATE_PAGE = "page"

        /** How far a finger has to travel sideways, and how much more than it travels up or down. */
        private const val SWIPE_DP = 64
        private const val SWIPE_RATIO = 2f

        /** The pages, and so the dots. */
        const val PAGE_COUNT = 5

        /** What the second page says about the setting that spots heels-flat squats. */
        private const val SMART_SENTENCE =
            "Squatting with your heels flat? That's a correct squat too. Choose Heels flat, " +
                "or turn on Spot heels-flat squats and Cindy switches to Adaptive Cindy by " +
                "itself after three of them, says so out loud, and counts them, the first " +
                "three included."

        private const val ADAPTIVE_SENTENCE =
            "Sessions with other movements are saved as an Adaptive Cindy and ranked against " +
                "your own sessions at the same movements."

        /** [replay] is true when the pages are opened again from Help. */
        fun intent(context: Context, replay: Boolean): Intent =
            Intent(context, TutorialActivity::class.java).putExtra(EXTRA_REPLAY, replay)
    }

    private val titles = listOf(
        "Cindy, counted for you",
        "Your Cindy, your movements",
        "Where to stand",
        "Before the clock starts",
        "Nothing leaves your phone"
    )

    private lateinit var binding: ActivityTutorialBinding
    private lateinit var profile: Profile
    private lateinit var back: TextView
    private lateinit var next: TextView
    private var replay = false
    private var index = 0
    private var forward = true
    private var touchX = 0f
    private var touchY = 0f

    private val page: LinearLayout get() = binding.page

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTutorialBinding.inflate(layoutInflater)
        setContentView(binding.root)
        profile = Profile(this)
        replay = intent.getBooleanExtra(EXTRA_REPLAY, false)
        index = (savedInstanceState?.getInt(STATE_PAGE) ?: 0).coerceIn(0, PAGE_COUNT - 1)

        binding.skip.setOnClickListener { finishPages() }
        binding.skip.describeAsButton("Skip the introduction")

        back = glassButton("BACK").apply { setOnClickListener { goTo(index - 1) } }
        next = primaryButton("NEXT").apply {
            setOnClickListener { if (index == PAGE_COUNT - 1) finishPages() else goTo(index + 1) }
        }
        binding.actions.addView(back)
        binding.actions.addView(next)

        // Back steps back through the pages, and out of the first one ends them as skipping does.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (index > 0) goTo(index - 1) else finishPages()
            }
        })

        show(animate = false)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(STATE_PAGE, index)
    }

    /**
     * A sideways swipe turns the page, judged after the touch has been delivered so that a swipe
     * that starts on a button does not also press it, and a scroll up or down is never mistaken
     * for one.
     */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            touchX = ev.x
            touchY = ev.y
        }
        val handled = super.dispatchTouchEvent(ev)
        if (ev.actionMasked == MotionEvent.ACTION_UP) {
            val dx = ev.x - touchX
            val dy = ev.y - touchY
            if (abs(dx) > dp(SWIPE_DP) && abs(dx) > SWIPE_RATIO * abs(dy)) {
                goTo(if (dx < 0) index + 1 else index - 1)
            }
        }
        return handled
    }

    private fun goTo(target: Int) {
        if (target !in 0 until PAGE_COUNT || target == index) return
        forward = target > index
        index = target
        show(animate = true)
    }

    /**
     * Builds the page at once and only then animates it in. The content is correct the moment a
     * button is pressed, whatever the animation is doing, so nothing can be tapped half way
     * between two pages.
     */
    private fun show(animate: Boolean) {
        page.removeAllViews()
        when (index) {
            0 -> welcome()
            1 -> adaptive()
            2 -> placement()
            3 -> counting()
            else -> privacy()
        }
        renderDots()
        renderButtons()
        binding.scroll.scrollTo(0, 0)
        if (animate) {
            page.alpha = 0f
            page.translationX = dp(24) * if (forward) 1f else -1f
            page.animate().alpha(1f).translationX(0f).setDuration(200L).start()
        }
        // Said rather than left to be discovered: a screen reader lands on the page change silent.
        page.announceForAccessibility(titles[index])
    }

    private fun renderDots() {
        binding.dots.removeAllViews()
        for (i in 0 until PAGE_COUNT) {
            binding.dots.addView(View(this).apply {
                background = dotDrawable(if (i == index) R.color.label else R.color.label_quaternary)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(8), dp(8)).apply { marginEnd = dp(8) })
        }
        binding.dots.contentDescription = "Page ${index + 1} of $PAGE_COUNT"
    }

    private fun renderButtons() {
        back.visibility = if (index == 0) View.GONE else View.VISIBLE
        next.text = when {
            index < PAGE_COUNT - 1 -> "NEXT"
            replay -> "DONE"
            else -> "LET'S GO"
        }
    }

    /**
     * However the pages end, they do not come back by themselves, and the tour of the camera
     * screen is next. A replay goes back to the camera screen, which brings it to the front and
     * closes the menu and help over it so that the tour has something to point at.
     */
    private fun finishPages() {
        FirstRun(this).finishPages()
        setResult(RESULT_OK)
        if (replay) {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            )
        }
        finish()
    }

    // ── the pages ─────────────────────────────────────────────────────────────

    private fun welcome() {
        page.addView(ImageView(this).apply {
            setImageResource(R.drawable.mark_arcs)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(96), dp(96)).apply {
            topMargin = dp(8)
            bottomMargin = dp(24)
        })
        title(titles[0])
        body(
            "Twenty minutes, as many rounds as you can of 5 pull-ups, 10 push-ups and 15 air " +
                "squats. Prop up your phone and the camera counts every rep."
        )
    }

    private fun adaptive() {
        title(titles[1])
        body(
            "Not doing strict pull-ups, full push-ups or deep squats yet? Pick the movements " +
                "you actually do — Cindy counts those too."
        )
        page.addView(InsetGroup(this).apply {
            row(movementRow("Band-assisted pull-ups", counted = true))
            row(movementRow("Push-ups from the knees", counted = true))
            row(movementRow("Heels-flat, on-toes or box squats", counted = true))
            row(movementRow("Inverted rows, incline push-ups and more", counted = false))
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(12) })
        card {
            addView(styledText(R.style.Cindy_Callout, SMART_SENTENCE).apply {
                setTextColor(getColor(R.color.label_body))
            })
        }
        footnote(ADAPTIVE_SENTENCE)
        page.addView(glassButton("CHOOSE MY MOVEMENTS").apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(54)
            ).apply { topMargin = dp(6) }
            setOnClickListener {
                chooseMovements(profile.movements) { chosen ->
                    profile.movements = chosen
                    Toast.makeText(this@TutorialActivity, chosen.label(), Toast.LENGTH_SHORT).show()
                }
            }
        })
    }

    private fun placement() {
        title(titles[2])
        body("The one thing you have to get right before the camera can help.")
        page.addView(PlacementGuideView(this).apply {
            setBackgroundResource(R.drawable.glass_card_small)
            setPadding(dp(12), dp(14), dp(12), dp(8))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(200)))
        page.addView(placementFacts())
    }

    private fun counting() {
        title(titles[3])
        bullet(
            "START checks your framing, then asks for two slow pull-ups so Cindy learns your " +
                "range. The clock starts itself once it has."
        )
        bullet(
            "The dot on the status line turns green when the next rep will count. When one " +
                "won't, the line says why — out loud too."
        )
        bullet("−1 and +1 fix a miscount any time. SKIP moves on to the next movement.")
    }

    private fun privacy() {
        title(titles[4])
        bullet("Counting happens on this phone. The picture is never uploaded.")
        bullet("REC films only when you tap it, and saves to your phone.")
        if (StravaConfig.available) bullet("Strava stays off until you connect it in the menu.")
        // Only the first run is about to be asked; someone replaying the pages has answered.
        if (!replay) footnote("Next, Android asks to use the camera.")
    }

    // ── building blocks ───────────────────────────────────────────────────────

    private fun title(text: String) = page.addView(
        styledText(R.style.Cindy_Title, text).apply { setPadding(dp(4), 0, dp(4), dp(12)) }
    )

    private fun body(text: String) = page.addView(
        styledText(R.style.Cindy_Body, text).apply {
            setTextColor(getColor(R.color.label_body))
            textSize = 16f
            setPadding(dp(4), 0, dp(4), dp(14))
        }
    )

    private fun footnote(text: String) = page.addView(
        styledText(R.style.Cindy_Footnote, text).apply { setPadding(dp(4), dp(2), dp(4), dp(10)) }
    )

    private fun bullet(text: String) = page.addView(LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setPadding(dp(4), 0, dp(4), dp(14))
        addView(View(context).apply {
            background = dotDrawable(R.color.label_tertiary)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(5), dp(5)).apply { topMargin = dp(9) })
        addView(styledText(R.style.Cindy_Body, text).apply {
            setTextColor(getColor(R.color.label_body))
            setPadding(dp(12), 0, 0, 0)
        })
    })

    private fun card(build: LinearLayout.() -> Unit) = page.addView(LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundResource(R.drawable.glass_card)
        setPadding(dp(20), dp(18), dp(20), dp(18))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(10) }
        build()
    })

    /**
     * One movement and what the app does with it: counted in green, because green is the colour
     * of what will count, or left for the athlete to tap in. Read as a single sentence.
     */
    private fun movementRow(label: String, counted: Boolean): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(52)
        setPadding(dp(18), dp(10), dp(16), dp(10))
        addView(styledText(R.style.Cindy_Body, label).apply {
            setTextColor(getColor(R.color.label_body))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        })
        addView(
            styledText(R.style.Cindy_Headline, if (counted) "counted" else "you tap +1").apply {
                setTextColor(getColor(if (counted) R.color.state_ok else R.color.label_secondary))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }.withStartMargin(dp(12))
        )
        // "+1" said as words, as the movement sheet says it: a bare glyph is not left to chance.
        contentDescription = "$label, ${if (counted) "counted" else "you tap plus one"}"
    }
}

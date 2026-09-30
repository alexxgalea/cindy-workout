package com.cindy.tracker

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.cindy.tracker.databinding.ActivityAccountBinding
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * The athlete: a name, a photo, and the badges their sessions have earned.
 *
 * There is no account, on purpose. Nothing here is signed in to or sent anywhere: the name and
 * the photo are kept on this phone like the records are, and travel only as far as the athlete's
 * own backup takes the rest. What makes this a screen of its own rather than a row in the menu is
 * the badges, which want a grid.
 *
 * The badges are not stored. They are worked out from the recorded sessions every time the
 * screen is drawn ([Badges]), so this screen cannot disagree with the record board, and clearing
 * the records clears them with it. The name and the photo are the athlete's rather than the
 * records', and are not cleared by that.
 */
class AccountActivity : AppCompatActivity() {

    private lateinit var binding: ActivityAccountBinding
    private lateinit var profile: Profile
    private lateinit var store: RecordStore

    /**
     * The system's photo picker: no permission to ask for, and on a phone that has not got one it
     * falls back to the document picker by itself. Registered before the screen starts, as it has
     * to be, and handed only the one picture the athlete chose.
     */
    private val pickPhoto = registerForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { picked -> if (picked != null) importPhoto(picked) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityAccountBinding.inflate(layoutInflater)
        setContentView(binding.root)
        profile = Profile(this)
        store = RecordStore(this)

        binding.actions.addView(primaryButton("DONE").apply {
            setOnClickListener { finish() }
        })
        render()
    }

    private fun toast(message: String) =
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

    /** Rebuilt rather than patched: a name, a photo or a badge sheet may just have changed it. */
    private fun render() {
        binding.rows.removeAllViews()
        val attempts = store.all()
        val zone = ZoneId.systemDefault()
        val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        val today = LocalDate.now()
        val earned = Badges.earned(attempts, zone, firstDay).associateBy { it.badge }

        binding.rows.addView(header(attempts, zone))
        binding.rows.addView(section("BADGES · ${earned.size} OF ${Badge.entries.size}"))
        for (family in BadgeFamily.entries) {
            binding.rows.addView(familyHeading(family))
            binding.rows.addView(grid(
                Badge.entries.filter { it.family == family }, earned, attempts, today, zone, firstDay
            ))
        }
    }

    // ── the athlete ───────────────────────────────────────────────────────────

    /**
     * The photo, the name, and one line about how long they have been at it.
     *
     * Both the photo and the name are tappable, and both say so to a screen reader: neither looks
     * like a button, which is exactly why each has to announce itself as one.
     */
    private fun header(attempts: List<Attempt>, zone: ZoneId): View {
        val name = profile.displayName
        val photo = AvatarStore.load(this)
        // Whether there is a file, not whether it drew: a photo that cannot be read is still one
        // the athlete can remove.
        val hasPhoto = AvatarStore.exists(this)

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(20), dp(22), dp(20), dp(20))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(12) }
        }

        card.addView(AvatarView(this).apply {
            show(photo, name)
            layoutParams = LinearLayout.LayoutParams(dp(88), dp(88))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            describeAsButton(if (hasPhoto) "Your photo, tap to change" else "Add a photo")
            setOnClickListener { choosePhoto(hasPhoto) }
        })

        card.addView(styledText(R.style.Cindy_Title2, name ?: "Add your name").apply {
            if (name == null) setTextColor(getColor(R.color.label_secondary))
            gravity = Gravity.CENTER
            minHeight = dp(48)
            setPadding(dp(12), dp(14), dp(12), dp(2))
            setOnClickListener { askName() }
            describeAsButton(
                if (name != null) "Your name, $name, tap to change" else "Add your name"
            )
        })

        card.addView(styledText(R.style.Cindy_Footnote, Badges.trainingLine(attempts, zone)).apply {
            gravity = Gravity.CENTER
        })
        return card
    }

    private fun choosePhoto(hasPhoto: Boolean) {
        val sheet = CindySheet(
            this,
            title = "Your photo",
            subtitle = "Pick a picture from your phone. It is cut to a square and a copy is kept " +
                "on this phone; the original stays where it is."
        )
        val choose = { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
        if (hasPhoto) {
            sheet.actions(
                primary = "CHOOSE PHOTO",
                onPrimary = choose,
                secondary = "REMOVE",
                onSecondary = {
                    if (!AvatarStore.clear(this)) toast("The photo could not be removed")
                    render()
                },
                secondaryTint = R.color.state_alert
            )
        } else {
            sheet.actions(
                primary = "CHOOSE PHOTO",
                onPrimary = choose,
                secondary = "CANCEL",
                onSecondary = {}
            )
        }
        sheet.show()
    }

    /**
     * Copies the chosen picture in off the main thread, which is where decoding a twelve
     * megapixel photo does not belong, then draws the result.
     */
    private fun importPhoto(uri: Uri) {
        lifecycleScope.launch {
            if (AvatarStore.import(this@AccountActivity, uri)) {
                render()
            } else {
                toast("That picture could not be used")
            }
        }
    }

    /**
     * The name, in a sheet with a field in it like the body-weight prompt. Emptying the field and
     * saving is how a name is taken back, and what it goes back to is "You".
     */
    private fun askName() {
        val input = EditText(this, null, 0, R.style.Cindy_Title2).apply {
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_VARIATION_PERSON_NAME or
                InputType.TYPE_TEXT_FLAG_CAP_WORDS
            setSingleLine()
            hint = "Your name"
            setHintTextColor(getColor(R.color.label_quaternary))
            gravity = Gravity.CENTER
            setBackgroundResource(R.drawable.glass_card_small)
            setPadding(dp(20), dp(16), dp(20), dp(16))
            filters = arrayOf(InputFilter.LengthFilter(Avatar.MAX_NAME))
            profile.displayName?.let { setText(it) }
            // A name already there is to be replaced, not appended to.
            setSelectAllOnFocus(true)
            isFocusableInTouchMode = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        val sheet = CindySheet(
            this,
            title = "Your name",
            subtitle = "Shown in the menu and beside your scores. Leave it empty to stay " +
                "“You”. It stays on this phone."
        )
        sheet.add(input)
        // The athlete opened this to type, so the keyboard comes up with it.
        input.post {
            if (input.requestFocus()) {
                (input.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                    ?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
            }
        }
        sheet.actions(
            primary = "SAVE",
            onPrimary = {
                profile.displayName = input.text.toString()
                render()
            },
            secondary = "CANCEL",
            onSecondary = {}
        ).show()
    }

    // ── the badges ────────────────────────────────────────────────────────────

    private fun section(title: String) = eyebrow(title).apply {
        setPadding(dp(4), dp(10), 0, dp(10))
    }

    private fun familyHeading(family: BadgeFamily) =
        eyebrow(family.label.uppercase(Locale.US)).apply {
            setPadding(dp(4), dp(14), 0, dp(8))
        }

    /** One family, in rows of [COLUMNS], on a card. */
    private fun grid(
        badges: List<Badge>,
        earned: Map<Badge, EarnedBadge>,
        attempts: List<Attempt>,
        today: LocalDate,
        zone: ZoneId,
        firstDay: DayOfWeek
    ): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(6), dp(6), dp(6), dp(6))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(4) }
        }
        for (line in badges.chunked(COLUMNS)) {
            card.addView(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                for (badge in line) {
                    val won = earned[badge]
                    val progress = if (won == null) {
                        Badges.progress(badge, attempts, today, zone, firstDay)
                    } else {
                        null
                    }
                    addView(tile(badge, won, progress, zone))
                }
                // A short last row keeps its tiles as wide as the rows above it.
                repeat(COLUMNS - line.size) {
                    addView(View(context), LinearLayout.LayoutParams(0, 0, 1f))
                }
            })
        }
        return card
    }

    /**
     * One badge: its disc, its name, and, while it is still to be earned, how far along it is.
     * The tile is a single control, so a screen reader hears one sentence for it.
     */
    private fun tile(
        badge: Badge,
        won: EarnedBadge?,
        progress: BadgeProgress?,
        zone: ZoneId
    ): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        setPadding(dp(4), dp(12), dp(4), dp(12))
        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        foreground = rowRipple()

        addView(badgeDisc(badge, earned = won != null))
        addView(styledText(R.style.Cindy_Footnote, badge.title).apply {
            gravity = Gravity.CENTER
            maxLines = 2
            setTextColor(getColor(if (won != null) R.color.label else R.color.label_secondary))
            setPadding(0, dp(8), 0, 0)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        })
        progress?.let {
            addView(styledText(R.style.Cindy_Footnote, it.label).apply {
                gravity = Gravity.CENTER
                maxLines = 2
                setPadding(0, dp(2), 0, 0)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            })
        }
        setOnClickListener { showBadge(badge, won, progress, zone) }
        describeAsButton(Badges.description(badge, won, progress, zone))
    }

    private fun showBadge(badge: Badge, won: EarnedBadge?, progress: BadgeProgress?, zone: ZoneId) {
        val sheet = CindySheet(this, title = badge.title, subtitle = badge.requirement)
        sheet.add(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4) }
            addView(badgeDisc(badge, earned = won != null, sizeDp = 56))
            addView(
                styledText(R.style.Cindy_Headline, Badges.status(won, progress, zone))
                    .withStartMargin(dp(16))
            )
        })
        sheet.actions(primary = "DONE", onPrimary = {}).show()
    }

    private companion object {
        /** Three to a row, which at 360dp leaves each tile room for a two-line title. */
        const val COLUMNS = 3
    }
}

package com.cindy.tracker

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.TextViewCompat
import com.cindy.tracker.databinding.ActivityHelpBinding

/**
 * What Cindy is, and what this app is doing while you do it.
 *
 * The workout half is CrossFit's, quoted rather than paraphrased and attributed on the page —
 * the definition, the scaled version, the score tiers and the pacing advice all come from
 * [SOURCE]. Note that CrossFit does *not* publish per-movement range-of-motion standards on that
 * page; it links out to a page per movement. So this screen does not state any either, rather
 * than inventing standards and putting CrossFit's name near them.
 *
 * The second half is this app's own, and is the part most worth reading: the camera cannot see
 * what it is not shown, and every hint it gives has a specific cause.
 */
class HelpActivity : AppCompatActivity() {

    private companion object {
        const val SOURCE = "https://www.crossfit.com/cindy"
    }

    private lateinit var binding: ActivityHelpBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityHelpBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.actions.addView(glassButton("CROSSFIT.COM").apply {
            // An arrow, because this one leaves the app.
            setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, R.drawable.ic_external, 0)
            compoundDrawablePadding = dp(8)
            TextViewCompat.setCompoundDrawableTintList(
                this, ColorStateList.valueOf(getColor(R.color.label_secondary))
            )
            setOnClickListener { openSource() }
            describeAsButton("Open the CrossFit page for Cindy")
        })
        binding.actions.addView(primaryButton("DONE").apply {
            setOnClickListener { finish() }
        })

        render()
    }

    private fun openSource() = openLink(SOURCE)

    private fun openLink(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, "No browser to open $url", Toast.LENGTH_LONG).show()
        }
    }

    private fun render() {
        // First, because it is the one thing on this screen that is for someone who is lost rather
        // than curious: the pages and the tour of the camera screen, taken again.
        binding.sections.addView(insetGroup {
            row(navRow("Take the tour", "The first-launch pages and a tour of the camera screen") {
                startActivity(TutorialActivity.intent(this@HelpActivity, replay = true))
            })
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) })

        heading("THE WORKOUT")
        workoutCard()
        quote(
            "Complete as many rounds and reps as possible in 20 minutes of: " +
                "5 pull-ups, 10 push-ups, 15 squats"
        )

        heading("SCALED")
        card {
            big("AMRAP 12:00")
            body("3 ring rows\n6 assisted push-ups\n9 squats")
            quiet("CrossFit's beginner version. This app always runs the 20-minute clock and " +
                "the 5, 10 and 15 reps, so it does not run this rep scheme — but it does count " +
                "scaled movements. Choose them under Movements in the menu: the camera counts " +
                "band-assisted pull-ups, push-ups from the knees and box squats, and you tap +1 " +
                "for the ones it cannot follow, such as inverted rows. Either way the session " +
                "is saved as an Adaptive Cindy.")
        }
        bullets(
            "Pull-ups scale to \"any movement that is an upper-body pulling option\" — " +
                "leg-assisted pull-ups, or ring rows.",
            "Push-ups scale to \"any bodyweight horizontal pressing movement, like an incline " +
                "push-up or push-up from the knees\".",
            "Squats scale on reps, or by squatting \"to a target that could be set above the " +
                "typical full range of motion\"."
        )
        paragraph(
            "Squatting with your heels flat? That is a correct squat too. Choose Heels flat under " +
                "Movements in the menu. Or turn on Spot heels-flat squats there: after three " +
                "heels-flat squats Cindy switches to Adaptive Cindy, says so out loud, and counts " +
                "them, the first three included. It is off by default while it is being tested."
        )

        heading("WHAT IT TESTS")
        quote(
            "Tests athletes' muscular endurance, stamina, and capacity with various low-skill " +
                "gymnastics elements."
        )
        paragraph(
            "Cindy is time-priority: the 20 minutes are fixed and you chase reps inside them. " +
                "That is why the clock here never stops for a rep and only pauses when you say so."
        )

        heading("WHAT A GOOD SCORE IS")
        paragraph("CrossFit's tiers, in rounds:")
        val history = RecordStore(this).all()
        // These tiers describe the prescribed movements, so only a standard Cindy is measured
        // against them. Ticking "Rx'd" off the back of a session run with knee push-ups would be
        // exactly the claim the note below has always refused to make -- the difference now is
        // that the app records which movements were used and can tell.
        val best = Records.bestIn(history, CindyProfile.STANDARD)
        // The scaled tier is deliberately never ticked: this app counts the prescribed rep
        // scheme, so it has no idea whether the work was scaled, and a tick there would be a
        // claim it cannot make.
        tier("Beginner", "8–10+ rounds, scaled", null, best)
        tier("Intermediate", "8–10+ rounds as prescribed", 8, best)
        tier("Rx'd", "20+ rounds", 20, best)
        tier("Elite", "25+ rounds", 25, best)
        val adaptiveBest = history.filter { it.profile?.isStandard != true }.maxByOrNull { it.totalReps }
        when {
            best != null ->
                quiet("Your best so far: ${best.scoreLabel()} — ${best.rounds} rounds.")
            // Not "no score": they have trained, and saying otherwise to someone whose sessions
            // were all adaptive would be the app pretending they were not there.
            adaptiveBest != null -> quiet(
                "Your best is ${adaptiveBest.scoreLabel()} at ${adaptiveBest.caption}. These " +
                    "tiers describe the prescribed movements, so it is ranked against your own " +
                    "sessions at the same movements instead."
            )
            else -> quiet("Finish a Cindy and your best will show up against these.")
        }
        quiet("The level on your session page, First Steps up to Legend, is this app's own " +
            "ladder and a separate, finer-grained scale. These four are CrossFit's.")

        heading("PACING")
        bullets(
            "\"The fastest athletes will complete rounds in under 45 seconds.\"",
            "\"Striving to complete each round in under 2 minutes is a great goal for all " +
                "levels to shoot for.\"",
            "The session page charts every round split, stacked by movement, so you can see " +
                "where the pace went."
        )
        quote(
            "If muscular failure and full range of motion are a concern with push-ups, consider " +
                "breaking up the reps early. For example, many athletes will start this workout " +
                "by performing 5 reps, taking a quick break to shake out their arms, and " +
                "completing the remaining 5 reps."
        )

        heading("RANGE OF MOTION")
        quote(
            "Adhering to the full range of motion in all movements is important for structural " +
                "integrity and joint health."
        )
        paragraph(
            "CrossFit keeps the standards for each movement on its own page rather than on the " +
                "Cindy page, so this screen does not restate them. Tap CROSSFIT.COM below and " +
                "follow the links to The Kipping Pull-up, The Push-up and The Air Squat."
        )

        heading("HOW THIS APP COUNTS")
        paragraph(
            "A phone on the floor sees a different shape than one at chest height, so nothing " +
                "here is a fixed angle. The app learns your range from your own movement and " +
                "judges reps against that."
        )
        diagram()
        bullets(
            "Stand the phone so your whole body stays in frame, and leave it there — moving it " +
                "mid-workout invalidates what it has learned, so a pause re-calibrates.",
            "START runs a setup check first: two slow pull-ups teach it your range. SKIP, " +
                "pressed during the check, asks and then goes straight in, calibrating as you go.",
            "For pull-ups it works out where your bar is from your dead hangs. The box on screen " +
                "is the bar zone your hands must be inside; the dashed line under it is where " +
                "your head has to drop back below before the next rep can count.",
            "Push-ups and squats do not start counting until you are actually in position — " +
                "\"Get set on the floor\", \"Stand up to start\". Getting up off the floor after " +
                "push-ups is not a squat.",
            "When a rep will not count, the status line says why, and says it out loud if " +
                "nothing changes. The voice can be turned off under Voice in the menu.",
            "−1 and +1 fix a miscount while the clock is running. Once it has started, SKIP " +
                "leaves the movement you are in for the next one: the reps you did in it stay counted, and " +
                "the rest are not made up.",
            "Once the clock has started, the stop button takes FLIP's place. It asks first, " +
                "then ends the workout early and saves your score so far."
        )

        voiceAndMusic()
        filming()
        sessionPage()
        comparing()
        lifted()
        heartRate()

        heading("CALORIES AND STREAKS")
        paragraph(
            "The calorie figure on the session page is an estimate, and it is labelled as one. " +
                "With no watch there is no honest way to measure this, so it uses the standard " +
                "MET equation that every strapless tracker uses underneath: " +
                "kcal = MET × 3.5 × your weight in kg ÷ 200, per minute."
        )
        bullets(
            "The Compendium of Physical Activities puts vigorous calisthenics and general " +
                "circuit training at 8 METs. That is taken to describe ten rounds in the " +
                "twenty minutes.",
            "Cindy is an AMRAP, so eight rounds and twenty-five rounds are not the same effort. " +
                "The MET is scaled by the rate you actually worked at, and capped at both ends — " +
                "no one sustains more than 14 METs for twenty minutes.",
            "Paused time is excluded. Resting with the clock stopped is not work.",
            "Nothing is shown until you enter your body weight, under Body weight in the menu " +
                "or from the session page, because a guessed weight would produce a confident " +
                "number that is wrong by however far the guess missed. It is stored on this " +
                "phone only."
        )
        paragraph(
            "A watch changes the method. When a paired watch was sending during the workout, " +
                "and your birth year and sex are set as well as your weight, the minutes it " +
                "covered use the Keytel et al. (2005) heart-rate equation, fitted separately " +
                "for women and men from measured energy expenditure. Any minute the watch did " +
                "not cover — a dropped connection, a reading that cannot be right — falls back " +
                "to the MET model for exactly that stretch, and the note under the figure says " +
                "how much came from which."
        )
        bullets(
            "Heart rate makes it a better estimate, not a measurement, and it stays labelled " +
                "as one.",
            "A session recorded with a watch before your details were set can use it once you " +
                "add them: the session page offers to, and the figure is worked out again.",
            "On the timeline the same estimate builds up across the workout, solid where your " +
                "heart rate measured a stretch and dashed where your reps estimated it. It ends " +
                "on the figure in Details."
        )
        paragraph(
            "The streak on the Progress screen counts consecutive days on which you trained, in " +
                "your own time zone. It does not break the moment midnight passes — a day you " +
                "have not finished living yet still counts as alive, so training this evening " +
                "keeps it going. The weekly streak does the same for weeks with at least one " +
                "session."
        )

        profileAndBadges()
        reminders()
        strava()
        privacy()

        heading("SOURCE")
        paragraph(
            "The workout, the scaled version, the score tiers and the pacing quotes on this " +
                "screen are from CrossFit's own page for Cindy."
        )
        quiet(SOURCE)
        quiet("Everything from HOW THIS APP COUNTS to this credit is this app's own, " +
            "not CrossFit's.")

        // Last, so it is the line a tester reads out when they report a problem. The debug build
        // carries its -debug suffix here, which is how the two builds are told apart on a phone.
        quiet("Cindy ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
    }

    // ── this app's own sections ───────────────────────────────────────────────

    private fun voiceAndMusic() {
        heading("VOICE AND MUSIC")
        paragraph(
            "Voice, under Voice in the menu, counts each rep out loud, calls the movement " +
                "changes and the clock, and says when you are in a position that will score. " +
                "It has a switch and a volume, and HEAR IT plays a sample."
        )
        bullets(
            "It speaks English, Spanish, French, German, Italian, Portuguese (Brazil), Dutch, " +
                "Polish, Romanian, Turkish or Russian. The screens stay in English; only what " +
                "is said aloud changes.",
            "The voices belong to your phone's speech engine, not to Cindy. Choosing a " +
                "language the phone does not have yet asks the engine to fetch it, and Manage " +
                "voices opens the engine's own screen if it will not come.",
            "A workout only uses voices stored on the phone, so counting works offline. If " +
                "your language is not there yet it counts in English and a note says so as " +
                "the workout starts.",
            "A language the engine does not speak at all is dimmed and cannot be chosen.",
            "The wording in the languages other than English has not been read by native " +
                "speakers yet."
        )
        paragraph(
            "Music, under Music in the menu, is one track you already have on the phone. It " +
                "plays while the clock runs, pauses when you pause, and drops in volume " +
                "whenever the voice speaks. Nothing is uploaded."
        )
    }

    private fun filming() {
        heading("FILMING")
        paragraph(
            "REC films the workout to Movies/Cindy on your phone, after a three-second " +
                "countdown that the voice counts too. The skeleton, clock, round, movement and " +
                "rep count are burned into the picture, with a CINDY watermark. There is no " +
                "sound."
        )
        bullets(
            "Filming through the setup check shows it for what it is. The clock panel says " +
                "SETUP, the round panel says CALIBRATION, and the movement is marked NOT " +
                "SCORED, with its count against the two calibration reps. They are not the " +
                "first two reps of a round.",
            "When the check passes, a CALIBRATED · 2 REPS banner is burned in for three " +
                "seconds as the clock starts. If you skipped the check it says CALIBRATION " +
                "SKIPPED instead."
        )
    }

    private fun sessionPage() {
        heading("THE SESSION PAGE")
        paragraph(
            "Every workout ends on its session page. Any session can be opened again from " +
                "Progress, as it was: tap a row on the leaderboard, tap a session in a day on " +
                "the calendar, or select a session on the chart and tap OPEN. Opened again it " +
                "is headed by its date, shows a single DONE, and has no streak, because a " +
                "streak describes today."
        )
        bullets(
            "Six tiles sit under the score: rounds, reps, time, average round, fastest and " +
                "slowest. Each says what it is made of, and a tile with nothing to say shows " +
                "a dash, never a zero.",
            "ROUND BY ROUND has a pill for every round, split into pull-ups, push-ups and " +
                "squats in the 5:10:15 proportions of the scheme, in the same three " +
                "brightnesses as the card at the top of this screen. It is filled by what you " +
                "actually did, so a round with a skipped set is hollow where it was skipped. " +
                "Tap a pill, or drag along them, to read one.",
            "MOVEMENTS gives each movement's reps, its time, its average finished set and its " +
                "share of the set time, in your own movement words: \"knee push-ups\", not " +
                "\"push-ups\".",
            "TIMELINE draws the session across its 20 minutes: your reps climbing, and your " +
                "heart rate and the calorie estimate beneath when there are any. Touch it or " +
                "drag along it and one cursor crosses every line, reading out the clock, the " +
                "round and movement, your reps by then, your heart rate, and how far ahead or " +
                "behind you were against the session you are comparing with.",
            "ROUND SPLITS is a bar for each round, stacked by movement. Taller is slower. " +
                "Tap or drag across the bars to read one, with a tick over each bar marking " +
                "the same round in the session you are comparing with. An outlined bar is a " +
                "round still under way when the clock stopped.",
            "DETAILS, at the foot, holds paused and real time, reps added by hand, how long " +
                "the camera lost you, the calorie estimate and the Strava upload."
        )
        paragraph(
            "Only what was recorded is shown, and nothing is worked out from the round count " +
                "to fill a gap. A session from before sets or rep times were kept shows less: " +
                "the tiles, and per-set steps on the timeline where that is all there is, with " +
                "a note under the chart saying so. Reps you tapped in count, and are named as " +
                "tapped in wherever they appear. A score the camera could not fully see says " +
                "\"at least\" wherever a figure comes from it."
        )
    }

    private fun comparing() {
        heading("COMPARING SESSIONS")
        paragraph(
            "COMPARED WITH sets the session against your best or your last time. A card gives " +
                "that session's date, score and reps, and how this one went: reps ahead or " +
                "behind, rounds, and how much faster or slower the average round was. Tap the " +
                "card to open that session. The choice also draws the dashed line on the " +
                "timeline and the ticks on the round splits."
        )
        bullets(
            "Only sessions at the same movements are compared. A band-assisted session is " +
                "never set against a strict one.",
            "Only earlier sessions are. A session is never measured against one that had not " +
                "happened yet, so opening an old one cannot credit it with a comparison a later " +
                "session earned.",
            "With no earlier session at the same movements there is no card, and the timeline " +
                "and splits are drawn on their own."
        )
    }

    private fun lifted() {
        heading("WHAT YOU LIFTED")
        paragraph(
            "Between the level and the comparison, one card puts the session in things you " +
                "can picture: how heavy it was in animals, and how much energy it burned in " +
                "cups of tea, phone charges or hours of an LED bulb. Never in food. The animal " +
                "changes from day to day, and a session opened again shows the one it showed " +
                "the first time."
        )
        paragraph(
            "Both are estimates, and a footnote on the card says how. A rep does not lift " +
                "all of your weight, only a share of it:"
        )
        bullets(
            "Pull-ups: 95%, because your hands and forearms stay on the bar.",
            "Push-ups: 64%, or 49% from the knees (Ebben et al., 2011).",
            "Air, heels-flat and box squats: 88%, the body above the knees.",
            "The total is your weight, times that share, times the reps you banked, added " +
                "up. Reps you tapped in count, and the card says so.",
            "Left out, and named on the card rather than guessed: band-assisted, foot-assisted " +
                "and negative pull-ups, inverted rows, incline push-ups and supported squats. " +
                "There is no share of your weight the app can stand behind for them.",
            "The energy is the calorie estimate from Details, so the two never disagree."
        )
        paragraph(
            "A session the camera could not fully see says \"at least\". A session from " +
                "before sets were timed shows the energy but no weight lifted. With no body " +
                "weight on file the card is one row asking for it."
        )
    }

    private fun heartRate() {
        heading("HEART RATE")
        paragraph(
            "Cindy can read the heart rate a watch or chest strap broadcasts, and uses it for " +
                "calories and on the session page. There is no heart-rate number on the camera " +
                "screen. It appears afterwards."
        )
        bullets(
            "Pair it under Heart rate in the menu, with FIND MY WATCH. The scan lasts twelve " +
                "seconds, you tap your device once, and after that it reconnects by itself " +
                "whenever the camera screen is open.",
            "Broadcast has to be on first. Garmin: Broadcast Heart Rate. Polar: share heart " +
                "rate with other devices. Chest straps broadcast whenever they are worn. Apple " +
                "Watch and most Wear OS watches do not broadcast a standard heart rate.",
            "A Garmin already linked to the phone through Garmin Connect is listed as " +
                "\"Connected to this phone\". If the sheet says it is connected but there is " +
                "no heart rate, broadcast is off on the watch.",
            "Android asks for Bluetooth permission the first time. On Android 11 and older " +
                "that is Location, which Cindy never reads, and Location has to be on for the " +
                "scan.",
            "Right after pairing it asks for your birth year and sex, if it does not have them. The calorie formula is " +
                "fitted separately for women and men and shifts with age, and the zones are " +
                "measured against a maximum worked out from your age. Prefer not to say uses " +
                "the average of the two formulas. Change them under Your details in the same " +
                "sheet.",
            "If a watch is paired but silent when you start, a note says calories will use " +
                "your reps until it arrives."
        )
        paragraph(
            "The heart-rate card on the session page gives your average and maximum, how much " +
                "of the clock the watch covered, your time in each of five zones, and your " +
                "hardest round: the finished round with the highest average among those the " +
                "watch saw for at least thirty seconds. The timeline gains a heart-rate line. " +
                "Average, maximum and zone time count only the time the watch covered. A gap is " +
                "left out, not averaged in as zero."
        )
        bullets(
            "Zones are shares of a maximum heart rate worked out from your age as " +
                "208 − 0.7 × age (Tanaka et al., 2001). That is an estimate, not a maximum " +
                "measured on you. Under 60% is Warm-up, then Easy from 60%, Aerobic from 70%, " +
                "Threshold from 80% and Maximum from 90%, with each zone's range printed beside it.",
            "Without your birth year the card keeps its figures and offers to ask for it, " +
                "rather than guessing an age.",
            "A watch can lag your effort by a few seconds.",
            "A session with no heart rate shows no card at all, and an older one shows " +
                "nothing rather than a guess."
        )
    }

    private fun profileAndBadges() {
        heading("YOU AND YOUR BADGES")
        paragraph(
            "The card at the top of the menu opens You: a name, a photo, and the badges your " +
                "sessions have earned. There is no account. Nothing is signed in to, and the " +
                "app uploads neither."
        )
        bullets(
            "Your name is used on the leaderboard, and \"You\" stands in until there is one.",
            "Your photo comes from the system photo picker, which needs no permission. The app " +
                "keeps its own small copy, so deleting the original loses nothing. Without one " +
                "the circle shows your initials.",
            "There are 26 badges in six families: sessions, rounds, streaks, volume, pace and " +
                "craft. Each is worked out from the sessions you have recorded, never handed " +
                "out for opening the app. A locked one says how far along you are, and a tap " +
                "opens what it asks for and when you won it.",
            "Badges for a score, the rounds and the pace, are earned only by a standard Cindy " +
                "the camera could stand behind, as a record is. The two pace badges are the " +
                "marks quoted under PACING. A session at other movements is a different " +
                "workout, not a lower score, and earns the badge for making it yours.",
            "The session page names up to three badges a session just earned, and counts the " +
                "rest.",
            "Clearing your records removes the badges with them, and keeps your name and photo."
        )
    }

    private fun reminders() {
        heading("REMINDERS")
        paragraph(
            "Off until you ask. Daily reminder in the menu sets the time, six in the evening " +
                "to start with, and TRY IT sends one now. There is at most one a day, and none " +
                "on a day you have already trained. It names the streak at stake, or the best " +
                "score to chase when there is none, and it never appears during a workout."
        )
        bullets(
            "It can arrive up to fifteen minutes after the time you set.",
            "Android 13 and newer asks to allow notifications when you switch it on. If they " +
                "are off the row says Blocked and offers the system settings.",
            "It is worked out on the phone. Nothing leaves it."
        )
    }

    private fun strava() {
        heading("STRAVA")
        paragraph(
            "Strava, in the menu, connects your Strava account on Strava's own page, in the " +
                "Strava app if you have it. Nothing is sent before you connect, and no video " +
                "or pose data is ever sent."
        )
        bullets(
            "Once connected, each finished workout uploads by itself as a Crossfit activity: " +
                "the score, every movement as a set with the reps actually banked, clock, " +
                "paused and real time, and calories when you have a body weight set, from " +
                "your heart rate when a watch recorded one. The heart-rate trace goes with it.",
            "Upload automatically is a switch in the Strava sheet, on by default. With it off " +
                "the Strava row under Details offers \"Upload\" instead. Finish a workout before " +
                "connecting and it offers \"Connect to upload\", which links the account and then " +
                "sends that workout.",
            "That row shows where the upload has got to: uploading, then a link to the " +
                "activity. If it fails it says so and you tap to retry, and if Strava needs " +
                "you to connect again it says that. The upload carries on in the background, " +
                "waits for a connection and retries by itself.",
            "Sessions from before you connected are not sent on their own; open one and use " +
                "its Strava row. One recorded before reps and sets were banked cannot be " +
                "described honestly, and says it is not available.",
            "DISCONNECT clears the connection from the phone at once and asks Strava to end " +
                "it. If Strava still lists Cindy Tracker at strava.com/settings/apps " +
                "afterwards, remove it there too."
        )
    }

    /**
     * What stays on the phone and what does not. Every line here is a claim about the code, and
     * Google Play holds the app to it: the store's Data safety answers and the published policy
     * say the same things, so a line is changed in all three or in none.
     */
    private fun privacy() {
        heading("PRIVACY")
        paragraph(
            "Cindy counts from the camera on your phone, and nearly everything it knows stays " +
                "there."
        )
        bullets(
            "The camera picture is read on the phone and thrown away. It is never saved or sent. " +
                "Video exists only if you tap REC, and it is saved to Movies/Cindy on the phone " +
                "like any other video.",
            "Your sessions, rep times, heart-rate traces, name, photo, body weight, birth year, " +
                "sex and settings are kept on the phone. Android's own backup may copy them to " +
                "your Google account, and to a new phone when you switch; that is Android's " +
                "backup, and you control it in Android's settings.",
            "Bluetooth is used only to find and read a heart-rate strap or watch. Android 11 and " +
                "older ask for the location permission for that scan; Cindy never reads your " +
                "location.",
            "Music is a track you pick. Cindy plays it and does not copy or send it. The voice " +
                "is your phone's speech engine: Cindy asks it for a voice installed on the " +
                "phone and gives it nothing but the words to say.",
            "There are no ads, no analytics, no account and no server of Cindy's."
        )
        if (StravaConfig.available) {
            bullets(
                "Strava is the one thing that leaves the phone, and only after you connect it. " +
                    "Each finished workout then sends Strava its score and sets with their reps, " +
                    "when it started, how long it took on the clock, paused and in real time, " +
                    "calories if a body weight is set, and the heart-rate trace if a watch " +
                    "recorded one. Never video, never the pose. Strava keeps what it receives " +
                    "under its own privacy policy."
            )
        }
        bullets(
            "To delete: CLEAR on the Progress screen removes your sessions with their rep times " +
                "and heart-rate traces; REMOVE on the Account screen removes the photo; " +
                "Android's Clear storage in the app's settings removes everything else, and so " +
                "does uninstalling. Videos in Movies/Cindy are yours to delete."
        )
        binding.sections.addView(
            insetGroup {
                row(navRow("Privacy policy", "Opens in your browser") {
                    openLink(AppLinks.PRIVACY_POLICY)
                })
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4) }
        )
    }

    // ── building blocks ───────────────────────────────────────────────────────

    /**
     * The rep scheme beside the mark whose proportions it is: the arcs are 270°, 180° and 90° of
     * a circle, which is fifteen, ten and five. The pips repeat the arcs' own weights, so the
     * mark on the launcher and the list in the card are visibly the same fact.
     */
    private fun workoutCard() {
        val weights = intArrayOf(R.color.label, R.color.label_secondary, R.color.label_tertiary)
        val scheme = listOf("5" to "Pull-ups", "10" to "Push-ups", "15" to "Air squats")

        card {
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL

                addView(ImageView(context).apply {
                    setImageResource(R.drawable.mark_arcs)
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(dp(62), dp(62)))

                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(
                        0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                    ).apply { marginStart = dp(18) }

                    addView(styledText(R.style.Cindy_Title2, "AMRAP 20:00"))
                    scheme.forEachIndexed { i, (count, name) ->
                        addView(LinearLayout(context).apply {
                            orientation = LinearLayout.HORIZONTAL
                            gravity = Gravity.CENTER_VERTICAL
                            setPadding(0, if (i == 0) dp(12) else dp(7), 0, 0)
                            addView(View(context).apply {
                                background = dotDrawable(weights[i])
                            }, LinearLayout.LayoutParams(dp(6), dp(6)))
                            addView(styledText(R.style.Cindy_Headline, count).apply {
                                gravity = Gravity.END
                                layoutParams = LinearLayout.LayoutParams(
                                    dp(22), ViewGroup.LayoutParams.WRAP_CONTENT
                                ).apply { marginStart = dp(10) }
                            })
                            addView(styledText(R.style.Cindy_Body, name).apply {
                                setTextColor(getColor(R.color.label_body))
                            }.withStartMargin(dp(10)))
                        })
                    }
                })
            })
            rule()
            quiet("One round is 30 reps. The score is rounds completed, plus any reps of the " +
                "round you are part-way through when the clock stops.")
        }
    }

    /**
     * The placement diagram, in its permanent home.
     *
     * It is offered once before the first setup check and can be dismissed for good there, so it
     * needs somewhere to live afterwards — this is the section that already gives the same advice
     * in words.
     */
    private fun diagram() = binding.sections.addView(
        PlacementGuideView(this).apply {
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(12), dp(14), dp(12), dp(8))
        },
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(210)).apply {
            topMargin = dp(4)
            bottomMargin = dp(14)
        }
    )

    private fun heading(text: String) {
        // A new section ends whatever group of tiers was being collected.
        tierGroup = null
        binding.sections.addView(eyebrow(text).apply { setPadding(dp(4), dp(24), 0, dp(10)) })
    }

    private fun paragraph(text: String) = binding.sections.addView(
        styledText(R.style.Cindy_Body, text).apply {
            setTextColor(getColor(R.color.label_body))
            setPadding(dp(4), 0, dp(4), dp(10))
        }
    )

    private fun quiet(text: String) = binding.sections.addView(
        styledText(R.style.Cindy_Footnote, text).apply { setPadding(dp(4), dp(2), dp(4), dp(10)) }
    )

    /**
     * CrossFit's words, marked as theirs by attribution rather than by a coloured bar.
     *
     * The bar down the side said "this is special"; the credit underneath says whose it is, which
     * is both the more useful fact and the one the screen is obliged to carry.
     */
    private fun quote(text: String) = binding.sections.addView(
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(20), dp(18), dp(20), dp(15))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }

            addView(styledText(R.style.Cindy_Body, "\u201C$text\u201D").apply {
                setTextColor(getColor(R.color.label_body))
                setTypeface(typeface, Typeface.ITALIC)
            })
            addView(View(context).apply {
                setBackgroundColor(getColor(R.color.hairline))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, hairlinePx()
                ).apply { topMargin = dp(14) }
            })
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(11), 0, 0)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                addView(ImageView(context).apply {
                    setImageResource(R.drawable.ic_link)
                    imageTintList = ColorStateList.valueOf(getColor(R.color.label_tertiary))
                }, LinearLayout.LayoutParams(dp(12), dp(12)))
                addView(eyebrow("CROSSFIT.COM").apply {
                    textSize = 10f
                    setPadding(dp(7), 0, 0, 0)
                })
            })
            contentDescription = "Quotation from crossfit.com: $text"
        }
    )

    private fun bullets(vararg items: String) = items.forEach { item ->
        binding.sections.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(4), 0, dp(4), dp(12))
            addView(View(context).apply {
                background = dotDrawable(R.color.label_tertiary)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(5), dp(5)).apply { topMargin = dp(9) })
            addView(styledText(R.style.Cindy_Body, item).apply {
                setTextColor(getColor(R.color.label_body))
                setPadding(dp(12), 0, 0, 0)
            })
        })
    }

    private fun card(build: LinearLayout.() -> Unit) = binding.sections.addView(
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.glass_card)
            setPadding(dp(20), dp(18), dp(20), dp(18))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }
            build()
        }
    )

    private fun LinearLayout.rule() = addView(View(context).apply {
        setBackgroundColor(getColor(R.color.hairline))
    }, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, hairlinePx()
    ).apply { topMargin = dp(16) })

    private fun LinearLayout.big(text: String) =
        addView(styledText(R.style.Cindy_Title2, text))

    private fun LinearLayout.body(text: String) =
        addView(styledText(R.style.Cindy_Body, text).apply {
            setTextColor(getColor(R.color.label_body))
            textSize = 16f
            setPadding(0, dp(8), 0, 0)
        })

    private fun LinearLayout.quiet(text: String) =
        addView(styledText(R.style.Cindy_Footnote, text).apply { setPadding(0, dp(12), 0, 0) })

    /** The tiers of the section being built, so four calls make one card rather than four. */
    private var tierGroup: InsetGroup? = null

    /**
     * One of CrossFit's score tiers, ticked when the athlete's best has reached it.
     *
     * A null [minRounds] is a tier this app cannot judge, and is never ticked.
     */
    private fun tier(name: String, detail: String, minRounds: Int?, best: Attempt?) {
        val group = tierGroup ?: InsetGroup(this).also {
            tierGroup = it
            binding.sections.addView(it)
        }
        val reached = minRounds != null && best != null && best.rounds >= minRounds

        group.row(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(14), dp(18), dp(14))
            if (reached) setBackgroundColor(getColor(R.color.surface_glass))

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                )
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                addView(styledText(R.style.Cindy_Headline, name))
                addView(styledText(R.style.Cindy_Footnote, detail).apply {
                    setPadding(0, dp(2), 0, 0)
                })
            })

            if (minRounds == null) {
                // Never ticked, and said so rather than left ambiguously empty: this app counts
                // the prescribed rep scheme, so it cannot know whether the work was scaled.
                addView(eyebrow("not scored").apply {
                    textSize = 10f
                    letterSpacing = 0.04f
                    setTextColor(getColor(R.color.label_quaternary))
                })
            } else {
                addView(ImageView(context).apply {
                    setImageResource(
                        if (reached) R.drawable.ic_check_filled else R.drawable.ic_ring_empty
                    )
                }, LinearLayout.LayoutParams(dp(22), dp(22)))
            }
            contentDescription =
                if (reached) "$name, $detail, reached" else "$name, $detail, not yet reached"
        })
    }
}

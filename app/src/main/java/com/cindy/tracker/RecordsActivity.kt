package com.cindy.tracker

import android.app.AlertDialog
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.cindy.tracker.databinding.ActivityRecordsBinding
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** The record board: the benchmark to chase, then every attempt logged on this phone. */
class RecordsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRecordsBinding
    private lateinit var store: RecordStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRecordsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        store = RecordStore(this)

        binding.btnBack.setOnClickListener { finish() }
        binding.btnClear.setOnClickListener { confirmClear() }
        render()
    }

    private fun confirmClear() {
        if (store.all().isEmpty()) return
        AlertDialog.Builder(this)
            .setTitle("Clear your records?")
            .setMessage("Every attempt logged on this phone will be deleted. The benchmark stays.")
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Clear") { _, _ ->
                store.clear()
                render()
            }
            .show()
    }

    private fun render() {
        val rows = binding.rows
        rows.removeAllViews()

        val mine = Records.ranked(store.all())
        val beaten = mine.firstOrNull()?.let { Records.beatsBenchmark(it) } == true

        rows.addView(
            row(
                rank = if (beaten) "2" else "1",
                name = Records.BENCHMARK_NAME,
                score = Records.BENCHMARK.scoreLabel(),
                detail = "the benchmark · ${Records.BENCHMARK.totalReps} reps",
                benchmark = true
            )
        )

        if (mine.isEmpty()) {
            rows.addView(empty())
            return
        }

        val dateFormat = SimpleDateFormat("d MMM yyyy", Locale.US)
        mine.forEachIndexed { i, a ->
            val outranks = Records.beatsBenchmark(a)
            rows.addView(
                row(
                    rank = if (outranks) "${i + 1}" else "${i + 2}",
                    name = if (i == 0) "You · best" else "You",
                    score = a.scoreLabel(),
                    detail = "${dateFormat.format(Date(a.atMillis))} · ${a.totalReps} reps",
                    benchmark = false
                )
            )
        }
    }

    private fun empty(): TextView = TextView(this).apply {
        text = "No attempts yet.\nFinish a 20-minute Cindy and it lands here."
        gravity = Gravity.CENTER
        setTextColor(getColor(R.color.on_surface_dim))
        textSize = 14f
        setPadding(0, dp(40), 0, 0)
    }

    private fun row(
        rank: String,
        name: String,
        score: String,
        detail: String,
        benchmark: Boolean
    ): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundResource(if (benchmark) R.drawable.bg_row_benchmark else R.drawable.bg_row)
        setPadding(dp(16), dp(14), dp(16), dp(14))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(10) }

        addView(TextView(context).apply {
            text = rank
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 16f
            width = dp(28)
        })

        addView(LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            addView(TextView(context).apply {
                text = name
                setTextColor(getColor(R.color.on_surface))
                textSize = 17f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            addView(TextView(context).apply {
                text = detail
                setTextColor(getColor(R.color.on_surface_dim))
                textSize = 12f
            })
        })

        addView(TextView(context).apply {
            text = score
            setTextColor(getColor(if (benchmark) R.color.accent else R.color.on_surface))
            textSize = 26f
            typeface = android.graphics.Typeface.MONOSPACE
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        })
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}

"""Seed script for SEO-focused marketing blog posts. Idempotent — skips slugs that already exist."""
from datetime import datetime, timedelta, timezone

from database import SessionLocal
from models import BlogPost, User, UserRole


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


C1 = """Every growing company eventually asks the same question: how do we run an internship program that actually works? A structured program converts ambitious students into high-performing future employees, while an unstructured one burns out mentors and produces no measurable return. This guide walks through the complete playbook for managing a modern internship program from kickoff to conversion.

## Start With Measurable Program Goals

Before the first intern walks in, define what success looks like. Common goals include converting 30% of the cohort into full-time hires, completing two shipped projects per intern, or cutting mentor administrative time below three hours per week. Write these numbers down. Every process decision downstream — attendance policy, review cadence, project scoping — should trace back to one of them.

## Design a Structured 8-Week Lifecycle

High-performing programs follow a repeatable lifecycle rather than improvising each week.

**Weeks 1 and 2: Onboarding.** Provision accounts, issue invite links bound to cohorts, assign mentors, and set shift schedules. Interns should check in on day one, not spend it waiting for credentials.

**Weeks 3 to 6: Core delivery.** Interns work a real sprint backlog on Kanban boards, log daily standups, and receive continuous mentor feedback. Every task moves visibly across a board so progress never lives only in someone's memory.

**Weeks 7 and 8: Evaluation and conversion.** Run 360-degree reviews covering technical skill, communication, and initiative. Compare ratings against attendance discipline and task throughput to make defensible hiring decisions.

## Centralize Operations in One System

Fragmented tooling is the silent killer of internship programs. Attendance lives in a spreadsheet, tasks live in chat messages, reviews live in email threads, and nobody can answer basic questions like who was late last week. A unified operations platform eliminates reconciliation work entirely: selfie-based geotagged attendance, sprint boards, standup logs, leave quotas, and appraisals all reference the same source of truth.

## Automate Discipline, Don't Police It

Manual oversight does not scale past ten interns. Automation scales indefinitely.

**Automated check-in windows** flag late arrivals without a mentor watching a clock. **Midnight auto-checkout** closes forgotten sessions so timesheets stay accurate. **Business-day leave calculators** exclude weekends automatically and sync approved leave straight into attendance records. The result is a program where rules enforce themselves and mentors spend their energy coaching instead of chasing.

## Close the Loop With Data

At the end of every cohort, leadership should be able to open a dashboard and see attendance streaks, completed task counts, review scores, and blocker frequency side by side. That combination turns the end-of-program hiring debate into a straightforward decision backed by evidence. Companies that measure this way consistently report higher intern-to-offer conversion rates and dramatically less mentor burnout.

## The Bottom Line

A great internship program is an operations problem before it is a talent problem. Set measurable goals, run a repeatable lifecycle, centralize your tools, automate discipline, and close every cohort with data. Do those five things consistently and your internship pipeline becomes your most reliable recruiting channel."""

C2 = """Ask any program coordinator how they track intern attendance and the answer is almost always the same: a spreadsheet, updated by hand, checked by nobody. It feels free. In reality it costs more than any software subscription — in proxy check-ins, payroll disputes, and hours of mentor admin time. Here is why spreadsheet tracking breaks down, and what a modern replacement looks like.

## The Five Failure Modes of Spreadsheet Attendance

**1. Proxy check-ins are invisible.** A friend can mark someone present from across the room. Without identity verification at check-in time, your attendance data measures who remembered to update a sheet, not who showed up.

**2. Data entry lags reality.** Manual sheets get filled at end of day, end of week, or never. By the time a pattern of absence emerges, the intervention window has closed.

**3. Late arrivals have no definition.** A spreadsheet cell says "9:15" but nothing decides whether that was on time. Every mentor applies their own standard, and fairness erodes.

**4. Leave and attendance live in separate worlds.** Approved leave days still show up as absences until somebody remembers to reconcile them manually.

**5. Nobody trusts the final report.** When conversion decisions rest on data everyone knows is unreliable, the data gets ignored.

## What Modern Attendance Tracking Looks Like

A purpose-built system replaces the honor system with verifiable events.

**Selfie check-ins** capture presence proof at the moment of check-in, making proxy marking pointless. **GPS validation against geofences** confirms the intern is physically at the office, remote hub, or client site you assigned. **Configurable cutoffs** decide late versus present automatically and identically for everyone. **Midnight auto-checkout** guarantees no session stays open forever, keeping hour totals accurate without reminders.

## The Payroll and Compliance Dividend

Verifiable timestamps change conversations. When an intern questions logged hours, you can show the exact check-in photo, coordinates, and reverse-geocoded address. When HR runs month-end reports, the export is already reconciled with approved leave. Disputes that used to take meetings now take seconds.

## Discipline Data Improves Mentoring

Attendance stops being a punishment ledger and becomes an early-warning signal. A streak of late arrivals flags a struggling intern weeks before a failed deliverable would. Mentors intervene with context instead of anecdotes, and interns know expectations apply equally to everyone because the system, not a person, draws the line.

## Making the Switch

Migration is simpler than most teams expect. Import your roster, define office geofences and shift windows, generate invite links, and let the system run. Programs that switch report the same reaction: they should have done it years ago, and the spreadsheet finally retires."""

C3 = """Your internship program's reputation is built in the first forty-eight hours. Interns who hit the ground running become advocates and high performers; interns who spend week one waiting for access tell their entire campus about it. These ten onboarding practices come from teams running large cohorts repeatedly, and every one of them is automatable.

## Before Day One

**1. Send tokenized invite links tied to cohorts.** Pre-bind each batch so interns self-register into the right team, department, and reporting line without HR shuffling spreadsheets.

**2. Provision accounts before arrival.** Credentials, role permissions, and shift schedules should exist when the intern first logs in — not three days after.

**3. Publish the shift contract early.** Check-in windows, late cutoffs, and leave quotas shared upfront eliminate 90% of first-week confusion.

## The First Forty-Eight Hours

**4. Make day-one check-in a milestone.** The first selfie check-in doubles as platform training and sends a clear signal: this program runs on verified, professional operations.

**5. Assign mentors explicitly.** Dual-mentor support — a primary plus co-mentors with full task and review permissions — prevents ownership gaps when someone is on leave.

**6. Ship a first ticket within 24 hours.** Confidence comes from moving a card across a board. Stage one small, winnable task on every intern's Kanban column before they arrive.

## The First Two Weeks

**7. Institute daily standups immediately.** Short structured logs of accomplishments, plans, and blockers normalize communication rhythm before bad habits form.

**8. Batch onboarding materials by department.** Engineering, design, and analytics tracks need different reading lists. Organize resources once, reuse forever.

**9. Schedule a week-two feedback pulse.** A quick structured review catches mismatched expectations while they are cheap to fix.

**10. Track onboarding as operations data.** First-week attendance, first-ticket completion time, and standup participation are your earliest predictors of cohort health. Watch them on a dashboard, not in anecdotes.

## Why Automation Makes the Difference

Every practice above has a manual version, and manual versions collapse at scale. Running five cohorts a year with fifty interns each means thousands of account setups, link generations, and schedule assignments. Platforms built for intern operations handle invite links, cohort placement, shift rules, and dashboards natively, which turns onboarding from a heroic effort into a checklist.

## The Compounding Return

Strong onboarding shows up months later in review scores, attendance discipline, and offer-conversion rates. Interns who feel operational clarity in week one treat the program — and your company — with professional seriousness. Treat onboarding as a product experience and your pipeline will fill itself."""

C4 = """Every internship program ends with the same meeting: leadership deciding which interns get offers. All too often the discussion runs on vibes — who seemed sharp, who spoke up in meetings. There is a better way. Teams that instrument their programs with verifiable performance data make faster decisions, defend them confidently, and convert more of their best people.

## The Problem With Subjective Conversion Decisions

Memory is a biased witness. The intern who chatted with leadership is remembered as engaged; the quiet intern who quietly cleared the most tickets is overlooked. Worse, subjective processes invite inconsistency between mentors evaluating identical performance. Candidates notice, and so do the mentors asked to defend choices they cannot substantiate.

## The Four Data Streams That Matter

**Attendance discipline.** Verified check-in streaks and punctuality rates measure professionalism better than any interview question. Consistency here predicts workplace reliability with uncanny accuracy.

**Task throughput and quality.** Completed tickets per sprint, cycle time across your Kanban board, and rework frequency show who delivers, not just who talks.

**360-degree review matrix.** Structured ratings from mentors across technical skill, communication, and initiative turn impressions into comparable numbers — especially when multiple mentors score the same intern independently.

**Standup signals.** Blocker frequency and resolution speed reveal who asks for help appropriately and who silently stalls. Great future hires unblock themselves fast.

## Building a Defensible Scorecard

Combine the streams into a simple weighted view: attendance discipline, delivery output, review ratings, and collaboration signals. Rank the cohort, calibrate with a mentor roundtable, and set your offer threshold before the final week. When the number one ranked intern is not the one anyone predicted, you can inspect the underlying records together — photos, boards, logs — instead of arguing over recollections.

## Timing the Offer Conversation

Data also tells you when to move. An intern trending upward through mid-program is a candidate for an early conversation, and top performers rarely stay on the market long. Conversely, a clear downward trend spares everyone an awkward non-offer by making the decision obvious weeks earlier.

## The Compounding Effect

Programs that convert interns using transparent data earn a reputation on campus: perform here and the offer is real. Applications rise, selectivity rises, and each cohort starts stronger than the last. Your internship program stops being charity with paperwork and becomes the top of your hiring funnel — measured, managed, and profitable."""

C5 = """Time theft has a friendly name in most offices: buddy punching. One intern marks another present, a manager backfills a sheet, and attendance integrity quietly dissolves. Studies of workforce time fraud consistently estimate losses in the billions annually, and unsupervised intern cohorts are among the easiest targets. Biometric-style selfie verification with GPS validation ends it — without turning managers into police officers.

## How Buddy Punching Actually Happens

The classic scenario needs no malice. A roommate says "can you mark me in, I'm twenty minutes away" and a friend taps the sheet. Multiply that by a hundred interns and a loose culture, and your attendance reports become fiction. Traditional fixes fail predictably: ID cards get handed to friends, and manual spot checks catch almost nothing.

## Selfie + GPS Verification, Explained

Modern verification binds every attendance event to two pieces of evidence captured at the same moment.

**A live selfie** proves the right human initiated the event. Stored securely alongside the record, it makes identity fraud effectively impossible — nobody checks in as someone else with their face.

**Geolocation against geofences** proves the event happened in the right place. Coordinates are validated against configured office boundaries and reverse-geocoded into a readable address, so remote and hybrid arrangements stay supported without losing rigor.

Together they transform attendance from a claim into a verifiable event.

## Addressing the Privacy Question Fairly

Cohorts sometimes push back on camera-and-location check-ins, and the response should be honest. The capture happens only at explicit check-in/check-out actions, photos are stored in access-controlled audit storage rather than public galleries, and location is evaluated at check-in time — not tracked continuously. Framing matters too: verified attendance protects honest interns, whose accurate records drive bonus eligibility and conversion decisions, from being diluted by dishonest ones.

## The Operational Side Effects

Teams adopting verified check-ins report benefits beyond fraud elimination. Late-arrival patterns surface instantly instead of at month end. Automated midnight checkout keeps timesheets complete. Payroll and stipend processing accelerates because exports need no manual cleanup. And the audit trail — timestamp, photo, coordinates, address — resolves every dispute with evidence instead of memory.

## Implementation Checklist

Rollout takes days, not months. Define office geofences and shift windows, set your late cutoff, import the roster via cohorts and invite links, then run a one-week parallel period where the old sheet and the new system coexist. When the numbers diverge, investigate — that gap is precisely the fraud and error you were previously blind to. Then retire the spreadsheet for good."""

C6 = """What predicts whether an intern becomes a great full-time hire? Most programs guess. They weigh interview impressions, mentor moods, and one polished final presentation. Meanwhile the real signals sit unused in operations data collected all along. Here are the KPIs that consistently separate future stars from polite goodbye emails.

## Leading Indicators Beat Final Impressions

Final-week evaluations suffer from recency bias: whatever happened last sprints colors everything. Leading indicators — captured continuously from week one — are harder to game and easier to compare across the whole cohort.

## The Six KPIs Worth Tracking

**1. Attendance punctuality rate.** Not raw presence — punctuality. Verified on-time check-in percentage is the single most reliable professionalism metric, and it correlates strongly with deadline behavior.

**2. Task completion velocity.** Average cycle time across Kanban stages shows who converts effort into finished work. Pair it with rework rate to separate fast from sloppy.

**3. Blocker resolution time.** How long does a flagged standup blocker stay active? Future hires either self-resolve quickly or escalate appropriately; chronic multi-day blockers signal a coaching opportunity.

**4. Standup consistency.** Missed logs cluster suspiciously near disengagement. Participation streaks are cheap to track and surprisingly predictive.

**5. Review rating slope.** A single 360-review snapshot lies; the trend between two review cycles does not. Rising trajectories identify late bloomers that static scores miss.

**6. Scope growth.** Did the intern's assigned tickets grow in complexity? Promotion of task difficulty is the clearest sign mentors trust the intern with real work — a judgment encoded in your board history for free.

## Turning Metrics Into a Fair Ranking

Weight the KPIs once, apply them uniformly, and publish the methodology to mentors before evaluation season. Uniformity matters more than perfect weights: a transparent formula applied consistently beats a secret one applied flexibly. When rankings surprise people, drill into the underlying records together — the evidence settles debates that opinions cannot.

## What These Metrics Are Not

None of this replaces human judgment; it disciplines it. Charisma, cultural contribution, and domain passion remain real factors. The point is to banish the invisible weighting where one loud voice outweighs eight weeks of verified delivery.

## Instrument Early, Decide Confidently

The uncomfortable truth is that most programs already collect this data — in spreadsheets, chat archives, and mentor memories — in forms too messy to use. Platforms built around intern operations capture it cleanly by default: verified attendance feeds punctuality rates, boards feed velocity, standups feed blocker metrics, and review cycles feed trend lines. Instrument the program early and the final ranking writes itself, defended by evidence every step of the way."""

BLOG_POSTS = [
    {
        "title": "How to Manage an Internship Program: The Complete 2026 Guide",
        "slug": "how-to-manage-an-internship-program",
        "excerpt": "A practical playbook for running internship cohorts that convert — measurable goals, a structured lifecycle, automated discipline, and data-driven conversion decisions.",
        "cover_image_url": "https://images.unsplash.com/photo-1522071820081-009f0129c71c?auto=format&fit=crop&w=1200&q=80",
        "tags": ["guide", "best practices"],
        "days_ago": 2,
        "content": C1,
    },
    {
        "title": "Intern Attendance Tracking: Why Spreadsheets Fail (and What Works)",
        "slug": "intern-attendance-tracking-spreadsheets-fail",
        "excerpt": "Spreadsheet attendance feels free but costs you proxy check-ins, payroll disputes, and mentor hours. Here's what verifiable tracking looks like instead.",
        "cover_image_url": "https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?auto=format&fit=crop&w=1200&q=80",
        "tags": ["guide", "engineering"],
        "days_ago": 9,
        "content": C2,
    },
    {
        "title": "10 Intern Onboarding Best Practices for Fast-Growing Teams",
        "slug": "intern-onboarding-best-practices",
        "excerpt": "Your program's reputation is built in the first 48 hours. Ten field-tested onboarding practices — every one automatable — for cohorts that start strong.",
        "cover_image_url": "https://images.unsplash.com/photo-1552664730-d307ca884978?auto=format&fit=crop&w=1200&q=80",
        "tags": ["best practices", "guide"],
        "days_ago": 16,
        "content": C3,
    },
    {
        "title": "How to Convert Interns Into Full-Time Hires Using Performance Data",
        "slug": "convert-interns-to-full-time-hires",
        "excerpt": "Stop deciding offers on vibes. Combine attendance discipline, task throughput, 360° reviews, and standup signals into a defensible conversion scorecard.",
        "cover_image_url": "https://images.unsplash.com/photo-1551434678-e076c223a692?auto=format&fit=crop&w=1200&q=80",
        "tags": ["guide", "product"],
        "days_ago": 23,
        "content": C4,
    },
    {
        "title": "Ending Buddy Punching: GPS Selfie Attendance for Intern Cohorts",
        "slug": "gps-selfie-attendance-end-buddy-punching",
        "excerpt": "Time theft thrives where attendance is self-reported. How selfie + geofence verification works, how to answer privacy concerns honestly, and a rollout checklist.",
        "cover_image_url": "https://images.unsplash.com/photo-1563986768609-322da13575f3?auto=format&fit=crop&w=1200&q=80",
        "tags": ["product", "engineering"],
        "days_ago": 30,
        "content": C5,
    },
    {
        "title": "Internship KPIs: 6 Metrics That Predict Hiring Success",
        "slug": "internship-kpis-that-predict-hiring-success",
        "excerpt": "Punctuality rate, task velocity, blocker resolution, review trends — the six operations metrics that reliably forecast which interns deserve an offer.",
        "cover_image_url": "https://images.unsplash.com/photo-1460925895917-afdab827c52f?auto=format&fit=crop&w=1200&q=80",
        "tags": ["best practices", "product"],
        "days_ago": 37,
        "content": C6,
    },
]


def get_author_id(db) -> int | None:
    author = (
        db.query(User)
        .filter(User.role.in_([UserRole.ADMIN, UserRole.SUPERADMIN]), User.is_active == True)  # noqa: E712
        .order_by(User.id)
        .first()
    )
    return author.id if author else None


def seed_blogs() -> None:
    db = SessionLocal()
    try:
        author_id = get_author_id(db)
        if not author_id:
            raise SystemExit("No active admin/superadmin user found. Bootstrap an admin first.")

        created, skipped = [], []
        for spec in BLOG_POSTS:
            if db.query(BlogPost).filter_by(slug=spec["slug"]).first():
                skipped.append(spec["slug"])
                continue
            published_at = _utcnow() - timedelta(days=spec["days_ago"])
            post = BlogPost(
                title=spec["title"],
                slug=spec["slug"],
                excerpt=spec["excerpt"],
                content=spec["content"].strip(),
                cover_image_url=spec["cover_image_url"],
                tags=",".join(spec["tags"]),
                status="published",
                author_id=author_id,
                published_at=published_at,
            )
            db.add(post)
            created.append(spec["slug"])

        db.commit()
        print(f"[INFO] Blog seeding complete. Created {len(created)}, skipped {len(skipped)} (already exist).")
        for slug in created:
            print(f"       + {slug}")
        for slug in skipped:
            print(f"       = {slug}")
    finally:
        db.close()


if __name__ == "__main__":
    seed_blogs()

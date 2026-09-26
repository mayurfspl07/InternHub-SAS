# InternHub Application: Complete UI Pages, Components & Container Architecture Map

> **Purpose**: This document provides a complete, exhaustive breakdown of every screen, layout container, widget, dialog, bottom sheet, and design token present in the InternHub Flutter application. It is specifically structured for planning a complete visual redesign, design system overhaul ("CSS/Theme reset"), and UI restructuring.

---

## 1. Design System Tokens & Global Styling Variables

Every visual element in the application currently inherits from these foundational token files:

### 1.1 Color Tokens (`lib/core/constants/app_colors.dart`)
- **Primary Brand**:
  - `primary`: `#7B61FF` (Cyber Lilac / Purple)
  - `primaryDark`: `#634AD8`
  - `primaryLight`: `#EDE9FE`
  - `secondary`: `#8B5CF6`
  - `accent`: `#38BDF8` (Sky Cyan)
- **Backgrounds & Canvas Surfaces**:
  - `backgroundLight`: `#F7F8FC` | `backgroundDark`: `#0F1117`
  - `surfaceLight`: `#FFFFFF` | `surfaceDark`: `#181A22`
  - `cardLight`: `#FFFFFF` | `cardDark`: `#1E212B`
  - `dockBackground`: `#161922` (Floating navigation dock)
  - `dockActive`: `#7B61FF` | `dockInactive`: `#8E95A5`
- **Vibrant Semantic Card Accents**:
  - `cardYellow` (`#FFE043`) / `cardYellowDark` (`#E5C522`)
  - `cardPurple` (`#8B5CF6`) / `cardPurpleLight` (`#DDD6FE`)
  - `cardPink` (`#F43F5E`) / `cardPinkLight` (`#FCE7F3`)
  - `cardBlue` (`#38BDF8`) / `cardBlueLight` (`#E0F2FE`)
  - `cardGreen` (`#34D399`) / `cardGreenLight` (`#D1FAE5`)
  - `cardOrange` (`#FB923C`) / `cardOrangeLight` (`#FFEDD5`)
- **Action & Status Colors**:
  - `success`: `#10B981` | `warning`: `#F59E0B` | `danger`: `#EF4444` | `info`: `#3B82F6`
  - `borderLight`: `#E5E7EB` | `borderDark`: `#2E3342`
  - `textPrimaryLight`: `#111827` | `textPrimaryDark`: `#F9FAFB`
  - `textSecondaryLight`: `#6B7280` | `textSecondaryDark`: `#9CA3AF`

### 1.2 Spacing & Border Radii (`lib/core/constants/app_spacing.dart`)
- **Paddings / Spacings**: `p4` (4px), `p8` (8px), `p12` (12px), `p16` (16px), `p20` (20px), `p24` (24px), `p32` (32px), `p40` (40px)
- **Border Radii**: `r8` (8px), `r12` (12px), `r16` (16px), `r20` (20px), `r24` (24px), `r28` (28px), `r32` (32px), `rPill` (999px)

### 1.3 Typography (`lib/core/constants/app_typography.dart`)
- **Headings Font**: `GoogleFonts.outfit` (displayLarge 32px w800, displayMedium 26px w700)
- **Body & Controls Font**: `GoogleFonts.plusJakartaSans` (titleLarge 20px w700, titleMedium 16px w600, bodyLarge 15px w400, bodyMedium 14px w400, labelLarge 13px w600, labelSmall 11px w500)

---

## 2. Global Shell & Navigation Framework

### 2.1 Navigation Wrapper & Scaffold (`lib/features/dashboard/main_navigation_wrapper.dart`)
- **Layout Structure**:
  - `Scaffold` root with persistent `CustomAppBar` at the top.
  - Body: `IndexedStack` switching between primary role screens.
  - Floating Bottom Dock: `FloatingBottomNav` positioned at `bottom: 0`.
  - Side Navigation: `_buildRoleAwareDrawer` with dynamic sections.
- **Top Bar (`CustomAppBar` - `lib/shared/widgets/custom_app_bar.dart`)**:
  - Organization Logo (`AppLogo.horizontal`)
  - Global Search Trigger Icon (opens `GlobalSearchModal`)
  - Role-Switch Indicator Pill
  - Notification Bell with unread badge counter (routes to `/notifications`)
  - User Avatar with status dot (opens bottom sheet with Profile & Logout)
- **Bottom Dock (`FloatingBottomNav` - `lib/shared/widgets/floating_bottom_nav.dart`)**:
  - Glassmorphic / Obsidian pill container (`AppColors.dockBackground`)
  - Intern Role Tabs: Dashboard | Attendance | Projects | Leave | Standup
  - Mentor & Admin Role Tabs: Dashboard | Attendance | Projects | Leave | Notices
- **Side Navigation Drawer (`_buildRoleAwareDrawer`)**:
  - **Header Container**: User Avatar, Full Name, Role Title Badge, Organization Logo.
  - **Intern Section**: Blogs, Standup, Assignments, Announcements, Notifications, My Profile.
  - **Mentor Section**: My Interns, Intern Assignments, Invite Links, Blogs, Standup, Reviews, Cohorts, Activity, Notifications, Profile.
  - **Admin Section**: User Directory, Team Directory, Invite Links & Signups, Intern Assignments, Blogs, Standup, Performance Reviews, Cohorts, Activity, Recycle Bin, Danger Zone (Data).
  - **Admin Masters Group**: Task Status, Project Status, Duration.
  - **Admin Settings Group**: Mail Configuration.
  - **Drawer Footer**: Destructive Log Out action button with confirmation dialog.

---

## 3. Detailed Page, Component & Container Inventory

### MODULE 1: Public & Authentication

#### 1.1 Splash Screen (`lib/splash_screen.dart`)
- **Route**: `/`
- **Containers & Components**:
  - `CurvedAnimation` & `AnimationController` background physics engine.
  - Floating particle canvas: 5 rotating feature pills (People, Tasks, Analytics, Calendar, Messages).
  - Central Branding Container: Glowing app logo container, animated headline, sub-headline.
  - Bottom Status Indicator: Animated loading pulse bar with auto-route decider (`token` check).

#### 1.2 Login Screen (`lib/features/auth/login_screen.dart`)
- **Route**: `/login` (or `/` fallback)
- **Containers & Components**:
  - Split Background: Gradient header backdrop with brand watermark.
  - Hero Card Container: Rounded card with elevation shadow.
  - Form Components:
    - Quick Role Select Chips (Intern / Mentor / Admin preset toggles).
    - Email / Phone Input Container with leading icon & validation helper.
    - Password Input Container with toggleable eye icon.
    - Remember Me checkbox & Forgot Password text link.
    - Submit Button: Full-width elevated `CustomButton` with arrow icon and loading spinner.
    - Countdown Banner: Retry throttle warning container on invalid attempts.
    - Footer Container: Link to Register / Join Organization.

#### 1.3 Signup Screen (`lib/features/auth/signup_screen.dart`)
- **Route**: `/signup`
- **Containers & Components**:
  - Header Container: Title, subtitle, return to sign-in button.
  - Form Container:
    - Full Name input field.
    - Official Email input field with domain validator.
    - Password & Confirm Password input fields with strength meter.
    - Terms & Privacy Agreement checkbox container.
    - Submit Button (`CustomButton`): "Create Intern Account".
    - Footer: "Already have an account? Sign In" text row.

#### 1.4 Join Invite Screen (`lib/features/auth/join_invite_screen.dart`)
- **Route**: `/join/:token`
- **Containers & Components**:
  - Token Verification Banner: Auto-validates token on load with loading skeleton.
  - Invite Details Card: Displays invited role, organization name, and inviter info.
  - Complete Registration Form:
    - Pre-filled/Locked Email container.
    - Full Name, Phone Number, Department, and Job Title input fields.
    - Set Password & Confirm Password fields.
    - Submit Button: "Accept Invite & Join Team".

---

### MODULE 2: Core Dashboards

#### 2.1 Intern Dashboard (`lib/features/dashboard/intern_dashboard_view.dart`)
- **Route**: `/dashboard` (when role == intern)
- **Containers & Components**:
  - Welcome Banner Card: Greeting with user name, avatar, animated time badge, and quick check-in pill.
  - Metrics Grid (2x2):
    - Overall Attendance Rate container with circular progress indicator.
    - Assigned Tasks Completed counter with progress bar.
    - Active Projects badge counter.
    - Leave Balance Days card.
  - Today's Standup Prompt Card: Status container showing if today's standup is submitted or pending, with "Log Standup" button.
  - Active Projects Carousel: Horizontal scrollable cards with project progress, deadline, and assigned tasks.
  - Recent Notices / Announcements Feed: Card listing top 3 broadcasts with urgency badges.

#### 2.2 Mentor Dashboard (`lib/features/dashboard/mentor_dashboard_view.dart`)
- **Route**: `/dashboard` (when role == mentor)
- **Containers & Components**:
  - Command Center Header Card: Mentor greeting, active interns count, and quick export action.
  - KPI Stat Cards:
    - Total Assigned Interns card with avatar stack preview.
    - Pending Leave Approvals count with direct badge trigger.
    - Pending Reviews count.
    - Active Mentored Projects count.
  - Action Queue Container:
    - Tabbed quick-action panel (Pending Leaves | Pending Reviews).
  - Assigned Interns Progress Table / List: Intern cards with avatar, department, current task, and attendance health status.
  - Today's Team Standup Summary Card: Progress bar showing percentage of interns who checked in and submitted standups.

#### 2.3 Admin Dashboard (`lib/features/dashboard/admin_dashboard_view.dart`)
- **Route**: `/dashboard` (when role == admin)
- **Containers & Components**:
  - Executive Overview Banner: Total headcount, system status badge, refresh button.
  - 4-Card Analytics Strip: Total Users | Attendance Today % | Active Projects | Pending Approvals.
  - Chart Containers (`lib/features/dashboard/widgets/dashboard_charts.dart`):
    - Attendance Trends Bar / Line Chart (weekly distribution).
    - Task Distribution Donut Chart (To Do, In Progress, Review, Completed).
  - Quick Administration Shortlink Grid: Master Settings, Data Management, Invite Links, Mail Config.
  - Recent System Activity Stream: Micro-feed of recent platform audits.

---

### MODULE 3: Attendance Tracking & Geofencing

#### 3.1 Attendance Home (`lib/features/attendance/attendance_home_screen.dart`)
- **Route**: `/attendance`
- **Containers & Components**:
  - Role-based resolver switching between `InternAttendanceScreen` and `StaffAttendanceScreen`.

#### 3.2 Intern Attendance Screen (`lib/features/attendance/intern_attendance_screen.dart`)
- **Containers & Components**:
  - Punch Card Container: Check-in / Check-out status, current working duration timer, biometric/geofence indicator.
  - Punch Button: Large rounded interactive button with gradient animation (`Check-in Now` / `Check-out Now`).
  - Monthly Calendar Heatmap / List: Day-by-day attendance status pills (Present, Absent, Half-Day, Holiday).
  - Monthly Statistics Pill Grid: Present Days | Late Check-ins | Half Days | Total Hours Worked.
  - Day Detail Modal Trigger: Opens `AttendanceDetailsModal` upon tapping any day.

#### 3.3 Staff Attendance Screen (`lib/features/attendance/staff_attendance_screen.dart`)
- **Containers & Components**:
  - Header Toolbar: Date picker selector, search input field, status filter pills (All, Present, Late, Absent).
  - Export Dialog Button: Opens `StaffAttendanceExportDialog` (Excel / CSV).
  - Intern Attendance List: Cards/rows with intern avatar, check-in time, check-out time, working duration, status badge, and drill-down arrow.
  - Quick Override Action: Three-dot menu trigger opening `AdminAttendanceOverrideModal`.

#### 3.4 Student Attendance Detail Screen (`lib/features/attendance/student_attendance_detail_screen.dart`)
- **Route**: `/attendance/:userId`
- **Containers & Components**:
  - Profile Summary Banner: Intern avatar, roll/ID number, email, assigned mentor, aggregate attendance percentage badge.
  - Date Range Filter Bar: "From Date" and "To Date" date pickers with reset button.
  - Attendance Log Table: Date | In Time | Out Time | Total Duration | Status | Notes.
  - Day Detail Modal Trigger (`AttendanceDayDetailModal`).

#### 3.5 Check-in / Check-out Screen (`lib/features/attendance/checkin_checkout_screen.dart`)
- **Containers & Components**:
  - Live GPS Map Container / Location verification indicator.
  - Live Time & Date Display widget.
  - Selfie / Camera Verification capture frame (`AuthedAttendanceImage`).
  - Work Notes / Daily Goal text input field.
  - Confirm Check-in Button with loading progress.

---

### MODULE 4: Projects & Task Kanban

#### 4.1 Projects List Screen (`lib/features/projects_tasks/projects_list_screen.dart`)
- **Route**: `/projects`
- **Containers & Components**:
  - Search & Filter Header: Search input textfield, date range picker, mentor filter dropdown.
  - Create Project FAB / Header Action: Opens `ProjectFormDialog` (admin/mentor).
  - Project View Toggle: Switch between Grid Card View and Table Row View.
  - Project Card Container (`VibrantCard`):
    - Project Title & Status Badge (Planning, Active, In Review, Completed).
    - Description snippet (max 2 lines).
    - Progress Bar (`SegmentedProgressBar`).
    - Deadline date badge & Assigned Members `AvatarStack`.
    - Tap action routing to `/projects/:projectId`.

#### 4.2 Project Detail Screen (`lib/features/projects_tasks/project_detail_screen.dart`)
- **Route**: `/projects/:projectId`
- **Containers & Components**:
  - Project Hero Header: Title, status pill, edit/delete actions, deadline timer, progress ring.
  - View Mode Segmented Control: Switch between `Kanban Board` and `Task List`.
  - Task Search & Filter Bar: Priority filter (Low, Medium, High), assignee filter dropdown.
  - Kanban Column Container (`TaskStatusColumn`):
    - Header with status color dot, name, and item counter.
    - Drag-and-drop / Scrollable list of `TaskModel` cards.
    - Add Task Button opening `CreateTaskBottomSheet`.
  - External Resources / Links Container: List of project links (GitHub, Figma, Docs) with "Add Link" dialog.
  - Discussion / Comments Board: Message thread list with input field and submit button.

#### 4.3 Task Detail Screen (`lib/features/projects_tasks/task_detail_screen.dart`)
- **Containers & Components**:
  - Task Title & Breadcrumb header.
  - Status & Priority Badges.
  - Assignee Card: Avatar, name, role.
  - Due Date & Estimated Hours counter.
  - Task Description container with markdown/rich text rendering.
  - Task Sub-checklist / Activity log stream.

---

### MODULE 5: Blogs & Knowledge Base

#### 5.1 Blogs List Screen (`lib/features/blogs/blogs_list_screen.dart`)
- **Route**: `/blogs`
- **Containers & Components**:
  - Tab Bar (Admin only): "Published Articles" vs "All & Drafts".
  - Search Bar & Tag Chips filter list.
  - Floating Action Button: "Write Article" (opens `BlogEditorDialog`).
  - Blog Card Container:
    - Cover Image with fallback gradient container.
    - Category tag pill & publication date badge.
    - Article Title (`GoogleFonts.outfit`).
    - Author Avatar and name row.
    - Reading time estimation pill.
    - Admin action buttons (Edit / Delete).
    - Tap action routing to `/blogs/:slug`.

#### 5.2 Blog Detail Screen (`lib/features/blogs/blog_detail_screen.dart`)
- **Route**: `/blogs/:slug`
- **Containers & Components**:
  - Back Button & Share action header.
  - Cover Image Banner.
  - Article Metadata Row: Category badge, published date, author name, reading time.
  - Article Title (`GoogleFonts.outfit` displayLarge).
  - HTML/Rich Body Renderer (`SafeHtmlView` - `lib/features/blogs/widgets/safe_html_view.dart`).
  - Author Bio Card footer with avatar and title.

---

### MODULE 6: Leave Management

#### 6.1 Leave Dashboard Screen (`lib/features/leaves/leave_dashboard_screen.dart`)
- **Route**: `/leave`
- **Containers & Components**:
  - Role-aware header: "My Leaves" (intern) vs "Leave Approval Queue" (admin/mentor).
  - Leave Balance Cards Strip (`LeaveBalanceCards`):
    - Casual Leave Card (used/remaining).
    - Sick Leave Card.
    - Total Leave Allowance Card.
  - Apply Leave Action Button: Opens `ApplyLeaveDialog` / `ApplyLeaveBottomSheet`.
  - Intern History List (`MyLeaveHistoryWidget`): Expandable cards with status badge (Pending, Approved, Rejected), dates, reason, and attachment preview (`LeaveAttachmentViewer`).
  - Mentor/Admin Approval Queue (`ManageLeaveQueueWidget`):
    - Pending application cards with intern avatar, department, date span, and reason.
    - Quick Action Buttons: "Approve" (green) and "Reject" (red) opening `ReviewLeaveDialog`.

---

### MODULE 7: Announcements & Notices

#### 7.1 Announcements Screen (`lib/features/announcements/announcements_screen.dart`)
- **Route**: `/announcements`
- **Containers & Components**:
  - Header Toolbar: Search field, priority filter (Normal, Important, Urgent), and "New Announcement" button (admin/mentor).
  - Announcement Feed Cards:
    - Priority Border Indicator (Red for Urgent, Yellow for Important, Purple for Normal).
    - Title, broadcast target badge (All, Interns, Mentors), and relative timestamp.
    - Content body container with rich preview.
    - Publisher Avatar and name footer.
    - Admin/Creator controls: Edit and Delete buttons.
  - Modal Trigger: Opens `AnnouncementDialog`.

---

### MODULE 8: Daily Standup

#### 8.1 Standup Screen (`lib/features/standup/standup_screen.dart`)
- **Route**: `/standup`
- **Containers & Components**:
  - Date Navigator Strip (`HorizontalDateStrip`): Horizontal calendar day-picker.
  - "My Today's Standup" Input Card:
    - Three Structured Text Areas:
      1. What did you accomplish yesterday?
      2. What are you working on today?
      3. Are there any blockers / impediments?
    - Submit / Update Standup Button with confirmation animation.
  - Team Feed Container (`StandupFeedScreen`):
    - Search input field to filter by member name.
    - Standup Entry Cards with intern avatar, submission timestamp, and 3-bullet answer blocks.
    - Blocker Alert Highlight Container (red-tinted box if blockers are listed).

---

### MODULE 9: Intern Assignments

#### 9.1 Assignments Screen (`lib/features/assignments/assignments_screen.dart`)
- **Route**: `/intern-assignments`
- **Containers & Components**:
  - Header: Tab controller ("Active Assignments", "Submitted", "Evaluated").
  - "Create Assignment" Button (admin/mentor) opening `AssignmentFormDialog`.
  - Assignment Card Container:
    - Assignment Title, Due Date countdown badge, Max Points pill.
    - Description box and reference links.
    - Intern Action: "Submit Work" button opening `SubmitAssignmentDialog`.
    - Mentor/Admin Action: "Review Submissions" opening `SubmissionsReviewDialog`.
    - Delete button trigger opening `DeleteAssignmentDialog`.

---

### MODULE 10: Performance Reviews

#### 10.1 Performance Dashboard Screen (`lib/features/performance/performance_dashboard_screen.dart`)
- **Route**: `/reviews` (Admin + Mentor only; Interns redirected)
- **Containers & Components**:
  - Header Toolbar: Search input, Rating filter pills (All, 5-Star, 4-Star, 3-Star, 2-Star, 1-Star), Project filter dropdown.
  - "Add Review" Button: Opens `CreateReviewBottomSheet` / `PerformanceReviewDialog`.
  - Review Card Container:
    - Intern Avatar, Name, and Department.
    - Project context tag.
    - Star Rating Display (`StarRatingBar`).
    - Review Summary snippet & Strengths / Improvements bullet points.
    - Evaluator name and evaluation date.
    - Details Action: Opens `ReviewDetailModal`.
    - Delete Action: Opens `DeleteReviewDialog`.

---

### MODULE 11: Directory & Cohorts

#### 11.1 Cohort Management Screen (`lib/features/directory_cohorts/cohort_management_screen.dart`)
- **Route**: `/cohorts` (Admin + Mentor only)
- **Containers & Components**:
  - Header with Search & "Create Cohort" action button (opens `CohortDialog`).
  - Cohort Card Container:
    - Cohort Name & Code badge (e.g., `SUMMER-2026-A`).
    - Date Span (Start Date to End Date).
    - Interns Enrolled count pill with `AvatarStack`.
    - Tap action opening `CohortDetailModal`.
    - Delete action opening `DeleteCohortDialog`.

#### 11.2 User Management Screen (`lib/features/directory_cohorts/user_management_screen.dart`)
- **Route**: `/admin` (Admin: Users; Mentor: My Interns)
- **Containers & Components**:
  - Role Filter Pills: All | Intern | Mentor | Admin.
  - Search Input field with debounce.
  - "Add User" Header Button (opens creation modal).
  - User List Item / Table Row:
    - `AppAvatar` with online status indicator.
    - Name, Email, Job Title, Department.
    - Role Chip (`StatusChip`).
    - 3-Dot Action Menu: Edit user, Reset password, Deactivate user.
    - User Profile Inspection: Opens `User360ProfileDialog`.

#### 11.3 Team Directory Screen (`lib/features/directory_cohorts/team_directory_screen.dart`)
- **Route**: `/team` (Admin only)
- **Containers & Components**:
  - Category filter pills (All, Leadership, Mentors, Engineering, HR).
  - Search input field.
  - Grid of Team Member Cards: Avatar, Name, Job Title, Department, Email link, Phone link.
  - Member Card Tap: Routes to `MemberProfileScreen`.

---

### MODULE 12: Tenant Operations & Activity

#### 12.1 Activity Timeline Screen (`lib/features/activity_audit/activity_timeline_screen.dart`)
- **Route**: `/activity` (Admin + Mentor only)
- **Containers & Components**:
  - Date group headers (Today, Yesterday, Last 7 Days).
  - Timeline Event Tile:
    - Vertical connector line with event-type icon dot (Create, Update, Delete, Checkin, Leave).
    - Actor Avatar & Name.
    - Action Description with bolded entity names.
    - Event Timestamp badge.
    - Metadata expandable drawer showing JSON diff / change payload.

#### 12.2 Recycle Bin Screen (`lib/features/activity_audit/recycle_bin_screen.dart`)
- **Route**: `/bin` (Admin only)
- **Containers & Components**:
  - Warning Banner: "Items in the recycle bin will be permanently purged after 30 days."
  - Filter Tabs: All | Tasks | Projects | Users | Assignments.
  - Deleted Item Card:
    - Item Name, Entity Type tag, Deleted By user, Deletion Date.
    - Action Buttons: "Restore" (green) and "Permanently Delete" (red danger button).

#### 12.3 Data Management Screen (`lib/features/admin_ops/data_management_screen.dart`)
- **Route**: `/data` (Admin only)
- **Containers & Components**:
  - Danger Zone Warning Container (Red border, red background tint).
  - Operation Cards:
    - Clear Test Attendance Data card.
    - Reset Platform Task States card.
    - Purge Inactive Invites card.
  - Security Confirmation Modal: Requires administrator password input before executing destructive batch API operations.

---

### MODULE 13: Administration Masters (Admin Only)

#### 13.1 Task Statuses Screen (`lib/features/masters/task_statuses_screen.dart`)
- **Route**: `/task-statuses`
- **Containers & Components**:
  - Description Banner: Workflow column master configuration.
  - "New Status" Button with dialog.
  - Reorderable List Container (`ReorderableListView`):
    - Color indicator swatch.
    - Status Name & System Key (e.g. `todo`, `in_progress`).
    - Default status toggle switch.
    - Drag handle icon & Delete action.

#### 13.2 Project Statuses Screen (`lib/features/masters/project_statuses_screen.dart`)
- **Route**: `/project-statuses`
- **Containers & Components**:
  - Master list of project life-cycle states (Planning, Active, On Hold, Completed, Archived).
  - Create / Edit Project Status Dialog.

#### 13.3 Internship Durations Screen (`lib/features/masters/internship_durations_screen.dart`)
- **Route**: `/internship-durations`
- **Containers & Components**:
  - Duration Tiers List: Cards showing tier name (e.g. "3 Months Internship"), duration in weeks/months, leave quota allocated, default onboarding tier toggle.
  - Create / Edit Duration Tier Dialog.

---

### MODULE 14: Settings & Mail Configuration

#### 14.1 Mail Configuration Screen (`lib/features/mail_settings/mail_configuration_screen.dart`)
- **Route**: `/admin/settings/mail` (Admin only)
- **Containers & Components**:
  - Segmented Tab Bar: "SMTP Configuration" vs "Mail Logs".
  - **Tab 1: Mail Config Panel (`MailConfigPanel` - `lib/features/mail_settings/widgets/mail_config_panel.dart`)**:
    - Host, Port, Username, Password input fields with test connection button.
    - Sender Email & From Name fields.
    - Security Type radio buttons (SSL, TLS, None).
    - Event Notification Preferences: Checkbox list for Welcome Emails, Leave Status Updates, Task Assignments.
    - Save Settings Button.
  - **Tab 2: Mail Logs Panel (`MailLogsPanel` - `lib/features/mail_settings/widgets/mail_logs_panel.dart`)**:
    - Search & status filter (Sent, Failed, Queued).
    - Mail Log Table: Recipient, Subject, Timestamp, Status Badge, Error details viewer modal.

---

### MODULE 15: User Profile & Notification Center

#### 15.1 Profile Screen (`lib/features/profile_settings/profile_screen.dart`)
- **Route**: `/profile` (All tenant roles)
- **Containers & Components**:
  - Profile Header Card:
    - User Avatar with change photo camera button.
    - Full Name, Role Chip, Department, Joining Date.
  - Information Card:
    - Contact Details (Email, Phone, Location).
    - Internship Details (Assigned Mentor, Cohort, Duration Tier).
  - Quick Actions Strip:
    - "Edit Profile" Button (opens `EditProfileDialog`).
    - "Change Password" Button (opens `ChangePasswordDialog`).
    - "Settings" Button (routes to `SettingsScreen`).
    - "Export My Data" action.

#### 15.2 Notification Center Screen (`lib/features/notifications/notification_center_screen.dart`)
- **Route**: `/notifications` (All tenant roles)
- **Containers & Components**:
  - Filter Chips: All | Unread | Announcements | Tasks | Leaves.
  - "Mark All as Read" Header Button.
  - Notification List:
    - Icon Container with category color.
    - Title, Body message, and relative time badge.
    - Unread indicator dot.
    - Swipe-to-dismiss background action.

---

## 4. Reusable Component & Widget Library (`lib/shared/widgets/`)

| Widget Name | File Path | Visual Elements & Controls |
|---|---|---|
| `AppAvatar` | `app_avatar.dart` | Circular/Squircle image with fallback initials and optional online status indicator dot. |
| `AppLogo` | `app_logo.dart` | Horizontal and compact brand logo with SVG/vector rendering. |
| `AvatarStack` | `avatar_stack.dart` | Overlapping row of user avatars with `+N more` circular badge. |
| `CustomAppBar` | `custom_app_bar.dart` | Top header bar containing menu trigger, logo, search icon, role badge, notification bell, and avatar. |
| `CustomButton` | `custom_button.dart` | Primary/Secondary rounded button supporting loading spinner, leading icon, and disabled states. |
| `CustomTextField` | `custom_text_field.dart` | Styled text input with label, prefix icon, suffix icon, border transitions, and error text. |
| `EmptyStateView` | `empty_state_view.dart` | Placeholder container with illustration icon, title, subtitle, and optional call-to-action button. |
| `FloatingBottomNav` | `floating_bottom_nav.dart` | Floating rounded bottom dock with icon animations, active glow indicator, and role-based items. |
| `GlobalSearchModal` | `global_search_modal.dart` | Full-screen or bottom-sheet search dialog querying across users, projects, tasks, and announcements. |
| `HorizontalDateStrip` | `horizontal_date_strip.dart` | Horizontal scrollable calendar selector with day name, date number, and active pill highlight. |
| `RoleSwitchBanner` | `role_switch_banner.dart` | Pill badge displaying active tenant role. |
| `SegmentedProgressBar`| `segmented_progress_bar.dart`| Multi-stage or single rounded progress track displaying percentage completion. |
| `StatusChip` | `status_chip.dart` | Pill tag with tailored background and text colors for roles, tasks, and attendance status. |
| `User360ProfileDialog`| `user_360_profile_dialog.dart`| Comprehensive profile overview modal showing performance, attendance stats, and contact actions. |
| `VibrantCard` | `vibrant_card.dart` | Signature candy-accent rounded card with customizable background tint, border, and tap callback. |

---

## 5. Complete Dialogs, Modals & Bottom Sheets Inventory

Every pop-up, modal, and bottom sheet across the entire application:

1. **Authentication & Profile**:
   - `ChangePasswordDialog` (`lib/features/profile_settings/change_password_dialog.dart`): Current password, new password, confirm password fields.
   - `EditProfileDialog` (`lib/features/profile_settings/widgets/edit_profile_dialog.dart`): Name, phone, department, bio fields.
   - `User360ProfileDialog` (`lib/shared/widgets/user_360_profile_dialog.dart`): 360-degree user summary.
2. **Projects & Tasks**:
   - `ProjectFormDialog` (`lib/features/projects_tasks/project_form_dialog.dart`): Project name, description, dates, mentor selection, member multi-select.
   - `CreateTaskBottomSheet` (`lib/features/projects_tasks/create_task_bottom_sheet.dart`): Task title, description, status, priority, assignee, due date.
3. **Attendance**:
   - `AttendanceDetailsModal` (`lib/features/attendance/attendance_details_modal.dart`): Detailed breakdown of single-day punch timestamps.
   - `AttendanceDayDetailModal` (`lib/features/attendance/widgets/attendance_day_detail_modal.dart`): Detailed day log.
   - `AdminAttendanceOverrideModal` (`lib/features/attendance/admin_attendance_override_modal.dart`): Admin manual attendance status and hours correction.
   - `StaffAttendanceExportDialog` (`lib/features/attendance/widgets/staff_attendance_export_dialog.dart`): Date range and format options for export.
   - `InternAttendanceExportDialog` (`lib/features/attendance/widgets/intern_attendance_export_dialog.dart`): Intern self-attendance export.
4. **Leaves**:
   - `ApplyLeaveDialog` / `ApplyLeaveBottomSheet` (`lib/features/leaves/widgets/apply_leave_dialog.dart`): Leave type selector, start/end date pickers, reason field, attachment upload.
   - `ReviewLeaveDialog` (`lib/features/leaves/widgets/review_leave_dialog.dart`): Approve/Reject selector with supervisor feedback notes.
   - `LeaveAttachmentViewer` (`lib/features/leaves/widgets/leave_attachment_viewer.dart`): Full-screen attachment viewer.
5. **Assignments**:
   - `AssignmentFormDialog` (`lib/features/assignments/widgets/assignment_form_dialog.dart`): Title, instructions, deadline, max score.
   - `SubmitAssignmentDialog` (`lib/features/assignments/widgets/submit_assignment_dialog.dart`): Submission notes and GitHub/file link input.
   - `SubmissionsReviewDialog` (`lib/features/assignments/widgets/submissions_review_dialog.dart`): Grade and feedback input for student submission.
   - `DeleteAssignmentDialog` (`lib/features/assignments/widgets/delete_assignment_dialog.dart`): Deletion confirmation.
6. **Blogs**:
   - `BlogEditorDialog` (`lib/features/blogs/widgets/blog_editor_dialog.dart`): Title, cover image URL, category dropdown, HTML content editor, publish toggle.
7. **Announcements**:
   - `AnnouncementDialog` (`lib/features/announcements/widgets/announcement_dialog.dart`): Title, content, priority picker, recipient target role selector.
8. **Performance Reviews**:
   - `CreateReviewBottomSheet` / `PerformanceReviewDialog` (`lib/features/performance/widgets/performance_review_dialog.dart`): Intern selector, project selector, 5-star rating, strengths, improvements.
   - `ReviewDetailModal` (`lib/features/performance/widgets/review_detail_modal.dart`): Detailed review card.
   - `DeleteReviewDialog` (`lib/features/performance/widgets/delete_review_dialog.dart`): Delete confirmation.
9. **Cohorts**:
   - `CohortDialog` (`lib/features/directory_cohorts/widgets/cohort_dialog.dart`): Cohort title, code, start date, end date.
   - `CohortDetailModal` (`lib/features/directory_cohorts/widgets/cohort_detail_modal.dart`): Member roster.
   - `DeleteCohortDialog` (`lib/features/directory_cohorts/widgets/delete_cohort_dialog.dart`): Delete confirmation.
10. **Search & Overlays**:
    - `GlobalSearchModal` (`lib/shared/widgets/global_search_modal.dart`): Live search filter dialog.

---

## 6. Structural & Styling Refactor Guide ("CSS Redesign Checklist")

When changing the look, CSS-equivalent properties, and layout structure of the application:

1. **Global Theme Reset**:
   - Edit [`lib/core/theme/app_theme.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/core/theme/app_theme.dart) for overall `ThemeData` (AppBar, CardTheme, InputDecorationTheme, ButtonTheme, DialogTheme).
   - Edit [`lib/core/constants/app_colors.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/core/constants/app_colors.dart) to replace colors across all light/dark surfaces.
   - Edit [`lib/core/constants/app_typography.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/core/constants/app_typography.dart) to change font families (e.g. Inter, Roboto, Geist) and size scales.
   - Edit [`lib/core/constants/app_spacing.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/core/constants/app_spacing.dart) to adjust global corner radiuses and grid paddings.
2. **Navigation Chrome**:
   - Edit [`lib/shared/widgets/custom_app_bar.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/shared/widgets/custom_app_bar.dart) to redesign the header bar.
   - Edit [`lib/shared/widgets/floating_bottom_nav.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/shared/widgets/floating_bottom_nav.dart) to alter the bottom dock shape, position, or blur effect.
   - Edit [`lib/features/dashboard/main_navigation_wrapper.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/features/dashboard/main_navigation_wrapper.dart) to redesign the slide-out Drawer navigation menu.
3. **Card & Component System**:
   - Edit [`lib/shared/widgets/vibrant_card.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/shared/widgets/vibrant_card.dart), [`custom_button.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/shared/widgets/custom_button.dart), and [`custom_text_field.dart`](file:///Users/rugveddhorje/Desktop/first_app/lib/shared/widgets/custom_text_field.dart) to redefine card elevation, borders, gradients, and input field outlines application-wide.

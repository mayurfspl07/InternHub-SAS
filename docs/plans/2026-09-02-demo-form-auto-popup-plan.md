# Demo Form Auto-Popup and Exit-Intent Implementation Plan

> **For Cursor / Antigravity:** Use executing-plans skill or subagent-driven development to implement this plan task-by-task.

**Goal:** Automatically open the demo form popup when visitors open the website, add desktop exit-intent re-engagement, and connect properly to the backend lead capture API.

**Architecture:** React state + `useEffect` hooks in `App.tsx` coordinating with `DemoModal.tsx`, using `sessionStorage` to prevent intrusive loops while maintaining instant on-demand CTA button responsiveness.

**Tech Stack:** React, TypeScript, Tailwind CSS, Framer Motion, Vite.

---

### Task 1: Enhance `DemoModal.tsx` for Flexible API URL & Submission State

**Files to modify:**
- `d:\download\internhub backend\marketing\src\components\layout\DemoModal.tsx`

**Steps:**
1. Update API target to use `import.meta.env.VITE_API_URL || 'https://internhub-sas-production.up.railway.app'` + `/api/leads`.
2. When submission succeeds, set `sessionStorage.setItem('internhub_demo_submitted', 'true')` to disable any exit-intent prompts.
3. Verify form input fields, phone, company, role, cohort size, message, and anti-spam honeypot.

---

### Task 2: Implement Auto-Open and Exit-Intent Detection in `App.tsx`

**Files to modify:**
- `d:\download\internhub backend\marketing\src\App.tsx`

**Steps:**
1. Add `useEffect` for initial landing:
   - Check `sessionStorage.getItem('internhub_demo_initial_shown')`.
   - If not present, trigger `setTimeout(() => setDemoModalOpen(true), 800)`.
   - Set `sessionStorage.setItem('internhub_demo_initial_shown', 'true')`.
2. Add `useEffect` for exit-intent detection:
   - Listen for `mouseleave` on `document`.
   - If `e.clientY <= 10` and neither `internhub_demo_exit_shown` nor `internhub_demo_submitted` is true in `sessionStorage`:
     - Open the modal.
     - Set `sessionStorage.setItem('internhub_demo_exit_shown', 'true')`.
   - Clean up event listener on unmount.

---

### Task 3: Build Verification and Typecheck

**Files to check:**
- Run `bun run build` or `npm run build` inside `d:\download\internhub backend\marketing` to verify TypeScript compile and bundling.
- Verify modal animations and responsiveness.

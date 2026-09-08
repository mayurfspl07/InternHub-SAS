# InternHub Backend REST API Documentation
> **Complete API Specification for Flutter Mobile & Web Client Integration**  
> **Backend Default Port:** `http://127.0.0.1:3001` (or your production API host)  
> **Base Path:** `/api`  
> **Authentication Scheme:** `Bearer <token>` in `Authorization` header  
> **Multi-Tenant Header:** `X-Organization-Id: <id>` (optional/tenant-scoped)

---

## 1. Architecture & Flutter Integration Guide

### 1.1 Base URLs by Environment
When connecting from Flutter, configure your `baseUrl` based on the target platform:

| Environment / Platform | Target API Base URL |
| :--- | :--- |
| **Android Emulator** | `http://10.0.2.2:3001` |
| **iOS Simulator** | `http://127.0.0.1:3001` |
| **Physical Device (LAN / Wi-Fi)** | `http://<YOUR_COMPUTER_LOCAL_IP>:3001` (e.g. `http://192.168.1.15:3001`) |
| **Production Server** | `https://api.yourdomain.com` |

### 1.2 Request & Response Conventions
- **Standard Headers:**
  ```http
  Accept: application/json
  Content-Type: application/json
  Authorization: Bearer <jwt_or_session_token>
  X-Organization-Id: <organization_id>
  ```
- **Multipart Uploads (Photos / Attachments):**
  - Use `multipart/form-data`.
  - **Do not** manually set `Content-Type: application/json` on upload requests.
- **Error Response Format:**
  ```json
  {
    "detail": "Descriptive error message or validation errors"
  }
  ```
- **HTTP Status Codes:**
  - `200 OK`: Request succeeded.
  - `201 Created`: Resource created.
  - `204 No Content`: Successful deletion or action with no response body.
  - `400 Bad Request`: Validation failure or invalid input parameters.
  - `401 Unauthorized`: Missing, expired, or invalid Bearer token.
  - `403 Forbidden`: User role lacks permission for this action.
  - `404 Not Found`: Resource does not exist.
  - `422 Unprocessable Entity`: Pydantic / schema validation error.
  - `429 Too Many Requests`: Rate-limited (check `Retry-After` header).
  - `500 Internal Server Error`: Backend error.

### 1.3 Recommended Flutter Packages
Add these dependencies to your Flutter `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.7.0                     # Powerful HTTP client with interceptors
  flutter_secure_storage: ^9.2.2  # Encrypted storage for auth tokens
  geolocator: ^13.0.2             # Device GPS coordinates for check-in
  image_picker: ^1.1.2            # Camera selfie capture for check-in
  shared_preferences: ^2.3.3      # Quick client-side flags/settings
```

---

## 2. Authentication & Session Management (`/api/auth`)

### 2.1 User Login
Authenticates an existing user and returns a Bearer session token.

- **Method & Path:** `POST /api/auth/login`
- **Auth Required:** No
- **Request Body (`application/json`):**
  ```json
  {
    "email": "intern@company.com",
    "password": "Password123!",
    "remember": true
  }
  ```
- **Response (`200 OK`):**
  ```json
  {
    "ok": true,
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "id": 4,
      "name": "Alex Johnson",
      "email": "intern@company.com",
      "role": "intern",
      "is_active": true,
      "department": "Engineering",
      "job_title": "Mobile App Developer Intern",
      "joining_date": "2026-06-01",
      "phone": "+91 9876543210",
      "mentor_id": 2,
      "mentor_name": "Sarah Miller",
      "organization_id": 1,
      "organization_name": "Tech Corp",
      "skills": ["Flutter", "Dart", "REST API"],
      "bio": "Building delightful cross-platform mobile apps.",
      "created_at": "2026-05-15T10:00:00Z"
    }
  }
  ```

### 2.2 Get Current User (`Me`)
Retrieves profile info for the currently authenticated user.

- **Method & Path:** `GET /api/auth/me`
- **Auth Required:** Yes (`Bearer <token>`)
- **Response (`200 OK`):**
  ```json
  {
    "id": 4,
    "name": "Alex Johnson",
    "email": "intern@company.com",
    "role": "intern",
    "is_active": true,
    "department": "Engineering",
    "job_title": "Mobile App Developer Intern",
    "joining_date": "2026-06-01",
    "phone": "+91 9876543210",
    "mentor_id": 2,
    "mentor_name": "Sarah Miller",
    "organization_id": 1,
    "organization_name": "Tech Corp",
    "skills": ["Flutter", "Dart"],
    "bio": "Building mobile apps.",
    "created_at": "2026-05-15T10:00:00Z"
  }
  ```

### 2.3 User Logout
Terminates the server session.

- **Method & Path:** `POST /api/auth/logout`
- **Auth Required:** Yes
- **Response (`200 OK`):**
  ```json
  {
    "ok": true,
    "message": "Logged out successfully"
  }
  ```

### 2.4 User Registration (Public)
- **Method & Path:** `POST /api/auth/register`
- **Auth Required:** No
- **Request Body:**
  ```json
  {
    "name": "John Doe",
    "email": "john@example.com",
    "password": "Password123!",
    "confirm_password": "Password123!",
    "role": "intern"
  }
  ```
- **Response (`200 OK`):**
  ```json
  {
    "user": {
      "id": 12,
      "name": "John Doe",
      "email": "john@example.com",
      "role": "intern",
      "is_active": false
    }
  }
  ```

### 2.5 Invite Token Verification
- **Method & Path:** `GET /api/auth/invite/{token}`
- **Auth Required:** No
- **Response (`200 OK`):**
  ```json
  {
    "valid": true,
    "label": "Summer 2026 Mobile Cohort",
    "mentor_name": "Sarah Miller"
  }
  ```

### 2.6 Register via Invite Token
- **Method & Path:** `POST /api/auth/invite/{token}/register`
- **Auth Required:** No
- **Request Body:**
  ```json
  {
    "name": "Emily Watson",
    "email": "emily@example.com",
    "password": "Password123!",
    "confirm_password": "Password123!",
    "phone": "+91 9876543210",
    "department": "Engineering",
    "job_title": "Flutter Intern",
    "joining_date": "2026-07-01"
  }
  ```
- **Response (`200 OK`):**
  ```json
  {
    "ok": true,
    "pending_approval": true,
    "message": "Account created. Awaiting admin approval."
  }
  ```

---

## 3. Dashboards (`/api/.../dashboard`)

### 3.1 Intern Dashboard
- **Method & Path:** `GET /api/intern/dashboard`
- **Auth Required:** Yes (`intern` role)
- **Response (`200 OK`):**
  ```json
  {
    "today_attendance": {
      "has_checked_in": true,
      "has_checked_out": false,
      "status": "present",
      "check_in": "2026-09-07T09:15:00Z",
      "check_out": null,
      "hours_worked": 4.5,
      "check_in_photo_url": "/api/attendance/152/photo/checkin",
      "check_out_photo_url": null,
      "check_in_address": "Bangalore Office, Floor 4"
    },
    "stats": {
      "present_today": 1,
      "total_days_logged": 45,
      "active_tasks": 3,
      "completed_tasks": 14,
      "active_projects": 2,
      "leave_balance_remaining": 6
    },
    "streak": 5,
    "recent_tasks": [
      {
        "id": 88,
        "title": "Build Splash Screen Animation",
        "status": "in_progress",
        "priority": "high",
        "project_name": "InternHub Flutter App",
        "deadline": "2026-09-10"
      }
    ],
    "announcements": [
      {
        "id": 14,
        "title": "All-Hands Meeting Tomorrow at 11:00 AM",
        "content": "Please join the meeting link on Google Meet.",
        "created_at": "2026-09-06T14:00:00Z"
      }
    ]
  }
  ```

### 3.2 Mentor Dashboard
- **Method & Path:** `GET /api/mentor/dashboard`
- **Auth Required:** Yes (`mentor` role)
- **Response (`200 OK`):** Contains intern list overview, pending review counts, active projects supervised, and today's attendance summary for mentor's students.

### 3.3 Admin Dashboard
- **Method & Path:** `GET /api/admin/dashboard`
- **Auth Required:** Yes (`admin` role)
- **Response (`200 OK`):** Organization stats, department breakdown, attendance metrics, project progress, and system audit feed.

### 3.4 Attendance Chart Breakdown
- **Method & Path:** `GET /api/dashboard/attendance-chart?month=YYYY-MM`
- **Auth Required:** Yes
- **Response (`200 OK`):**
  ```json
  {
    "month": "2026-09",
    "daily_records": [
      { "date": "2026-09-01", "hours": 8.0, "present": 28, "status": "present" },
      { "date": "2026-09-02", "hours": 7.5, "present": 30, "status": "present" }
    ]
  }
  ```

---

## 4. Attendance System (`/api/attendance`)

### 4.1 Today's Attendance
Retrieves the logged-in user's attendance status for today.

- **Method & Path:** `GET /api/attendance/today`
- **Auth Required:** Yes
- **Response (`200 OK`):**
  ```json
  {
    "today": "2026-09-07",
    "record": {
      "id": 204,
      "user_id": 4,
      "date": "2026-09-07",
      "check_in": "2026-09-07T09:05:12Z",
      "check_out": null,
      "hours_worked": 0.0,
      "status": "present",
      "check_in_location": {
        "lat": 12.9716,
        "lng": 77.5946,
        "address": "Bangalore Central, Karnataka"
      },
      "check_in_photo_url": "/api/attendance/204/photo/checkin"
    }
  }
  ```

### 4.2 Check-In (Photo + GPS Location)
Uploads an image selfie and GPS coordinates to check in.

- **Method & Path:** `POST /api/attendance/check-in`
- **Auth Required:** Yes
- **Content-Type:** `multipart/form-data`
- **Form Fields:**
  - `photo`: File (image JPEG/PNG selfie)
  - `lat`: `string` / `number` (e.g. `12.971598`)
  - `lng`: `string` / `number` (e.g. `77.594562`)
- **Response (`200 OK`):** Returns the newly created `AttendanceRecord`.

### 4.3 Check-Out (Photo + GPS Location)
Uploads an image selfie and GPS coordinates to check out.

- **Method & Path:** `POST /api/attendance/check-out`
- **Auth Required:** Yes
- **Content-Type:** `multipart/form-data`
- **Form Fields:**
  - `photo`: File (image JPEG/PNG selfie)
  - `lat`: `string` / `number`
  - `lng`: `string` / `number`
- **Response (`200 OK`):** Returns the updated `AttendanceRecord` with `check_out` and `hours_worked`.

### 4.4 Attendance History (Calendar / Monthly View)
- **Method & Path:** `GET /api/attendance/history`
- **Auth Required:** Yes
- **Query Parameters:**
  - `page`: `number` (default: `1`)
  - `page_size`: `number` (default: `31` for full month)
  - `month`: `string` (`YYYY-MM`, optional)
- **Response (`200 OK`):**
  ```json
  {
    "page": 1,
    "total_pages": 1,
    "total": 22,
    "records": [
      {
        "id": 201,
        "date": "2026-09-01",
        "check_in": "2026-09-01T09:00:00Z",
        "check_out": "2026-09-01T17:30:00Z",
        "hours_worked": 8.5,
        "status": "present"
      }
    ]
  }
  ```

### 4.5 Fetch Attendance Selfie Photo
- **Method & Path:** `GET /api/attendance/{attendanceId}/photo/{kind}`
  - `kind`: `checkin` or `checkout`
- **Auth Required:** Yes (`Bearer <token>`)
- **Response (`200 OK`):** Returns the binary image data (`image/jpeg`).

### 4.6 Export My Attendance CSV
- **Method & Path:** `GET /api/attendance/my/export?from_date=YYYY-MM-DD&to_date=YYYY-MM-DD`
- **Auth Required:** Yes
- **Response (`200 OK`):** CSV file stream.

---

## 5. Projects & Task Board (`/api/projects`)

### 5.1 List Projects
- **Method & Path:** `GET /api/projects`
- **Auth Required:** Yes
- **Query Parameters:**
  - `search`: `string`
  - `status`: `string` (`planning`, `in_progress`, `completed`, `on_hold`)
  - `mentor_id`: `number`
  - `page`: `number`
  - `page_size`: `number`
- **Response (`200 OK`):**
  ```json
  {
    "page": 1,
    "total_pages": 1,
    "total": 3,
    "projects": [
      {
        "id": 10,
        "name": "InternHub Mobile App",
        "description": "Flutter-based cross-platform client app",
        "status": "in_progress",
        "progress": 65,
        "start_date": "2026-08-01",
        "end_date": "2026-10-31",
        "mentor_id": 2,
        "mentor_name": "Sarah Miller",
        "tasks": [],
        "members": [
          { "id": 4, "name": "Alex Johnson", "role": "intern" }
        ],
        "task_count": 18,
        "task_done": 12,
        "created_at": "2026-08-01T09:00:00Z"
      }
    ]
  }
  ```

### 5.2 Get Project Details (with Kanban Tasks & Members)
- **Method & Path:** `GET /api/projects/{id}`
- **Auth Required:** Yes
- **Response (`200 OK`):** Full project object with nested `tasks`, `members`, and status breakdown.

### 5.3 Create Project (Admin / Mentor)
- **Method & Path:** `POST /api/projects`
- **Request Body:**
  ```json
  {
    "name": "E-Commerce Microservices",
    "description": "Building backend order service",
    "status": "planning",
    "start_date": "2026-10-01",
    "end_date": "2026-12-31",
    "mentor_id": 2
  }
  ```

### 5.4 Update Project
- **Method & Path:** `PUT /api/projects/{id}`
- **Request Body:** Partial project fields to update.

### 5.5 Delete Project
- **Method & Path:** `DELETE /api/projects/{id}`

---

### 5.6 Project Tasks (`/api/projects/tasks`)

#### Create Task
- **Method & Path:** `POST /api/projects/{projectId}/tasks`
- **Request Body:**
  ```json
  {
    "title": "Integrate Biometric Login",
    "description": "Use local_auth package to support FaceID and Fingerprint",
    "priority": "high",
    "status": "todo",
    "assigned_to": 4,
    "deadline": "2026-09-20"
  }
  ```
- **Response (`201 Created`):** Returns created `Task` object.

#### Update Task (Status Drag-and-Drop / Details)
- **Method & Path:** `PUT /api/projects/tasks/{taskId}`
- **Request Body:**
  ```json
  {
    "status": "in_progress",
    "priority": "urgent",
    "title": "Integrate Biometric Login"
  }
  ```

#### Delete Task
- **Method & Path:** `DELETE /api/projects/tasks/{taskId}`

---

### 5.7 Task Comments & Attachments

#### List Task Comments
- **Method & Path:** `GET /api/projects/tasks/{taskId}/comments`

#### Add Comment to Task
- **Method & Path:** `POST /api/projects/tasks/{taskId}/comments`
- **Content-Type:** `multipart/form-data`
- **Form Fields:**
  - `body`: `string` (comment message text)
  - `file`: `File` (optional file attachment)

#### Upload Task Attachment
- **Method & Path:** `POST /api/projects/tasks/{taskId}/attachments`
- **Content-Type:** `multipart/form-data`
- **Form Fields:**
  - `file`: `File` (binary document/image)
  - `description`: `string` (optional note)

#### Download Task Attachment
- **Method & Path:** `GET /api/projects/tasks/attachments/{attachmentId}/download`

---

## 6. Leave Management (`/api/leave`)

### 6.1 Get My Leave Status & Quota Balance
- **Method & Path:** `GET /api/leave/mine`
- **Auth Required:** Yes
- **Response (`200 OK`):**
  ```json
  {
    "balance": {
      "quota": 12,
      "used": 4,
      "pending": 1,
      "remaining": 7,
      "available_after_pending": 7
    },
    "summary": {
      "total": 5,
      "approved": 4,
      "pending": 1,
      "rejected": 0,
      "days_taken": 4,
      "days_pending": 2
    },
    "requests": [
      {
        "id": 31,
        "user_id": 4,
        "start_date": "2026-09-15",
        "end_date": "2026-09-16",
        "days": 2,
        "leave_type": "sick",
        "reason": "Viral fever recovery",
        "status": "pending",
        "created_at": "2026-09-07T12:00:00Z"
      }
    ]
  }
  ```

### 6.2 Apply for Leave
- **Method & Path:** `POST /api/leave`
- **Content-Type:** `multipart/form-data` (or `application/json` if no attachment)
- **Form Fields:**
  - `start_date`: `string` (`YYYY-MM-DD`)
  - `end_date`: `string` (`YYYY-MM-DD`)
  - `leave_type`: `string` (`sick`, `casual`, `academic`, `other`)
  - `reason`: `string`
  - `attachment`: `File` (optional medical certificate/proof)
- **Response (`200 OK`):** Created `LeaveRequest`.

### 6.3 Review Leave Request (Admin / Mentor)
- **Method & Path:** `POST /api/leave/{id}/review`
- **Auth Required:** Yes (`admin` or `mentor`)
- **Request Body:**
  ```json
  {
    "decision": "approved",
    "comment": "Take care and rest well."
  }
  ```

---

## 7. Daily Standup Logs (`/api/standup`)

### 7.1 Today's Standup Entry
- **Method & Path:** `GET /api/standup/today`
- **Auth Required:** Yes
- **Response (`200 OK`):** Returns existing standup log or `null` if not submitted yet today.

### 7.2 Submit Daily Standup
- **Method & Path:** `POST /api/standup`
- **Auth Required:** Yes
- **Request Body:**
  ```json
  {
    "date": "2026-09-07",
    "did": "Implemented Flutter biometric authentication and camera selfie capture.",
    "plan": "Complete state management using Bloc/Provider and write unit tests.",
    "blockers": "Waiting for backend CORS config on attendance selfie preview.",
    "mood": "happy"
  }
  ```
- **Response (`200 OK`):** Returns submitted `StandupLog`.

### 7.3 Standup History
- **Method & Path:** `GET /api/standup?from=YYYY-MM-DD&to=YYYY-MM-DD&page=1&page_size=15`

---

## 8. Assignments & Submissions (`/api/assignments`)

### 8.1 List Assignments
- **Method & Path:** `GET /api/assignments`
- **Query Parameters:** `status` (`pending`, `submitted`, `reviewed`, `all`), `page`, `page_size`, `search`
- **Response (`200 OK`):**
  ```json
  {
    "page": 1,
    "total_pages": 1,
    "total": 2,
    "items": [
      {
        "id": 18,
        "title": "Week 3 Assignment: Flutter State Management",
        "description": "Implement a shopping cart with persistent local storage",
        "due_date": "2026-09-14T23:59:59Z",
        "status": "pending",
        "max_score": 100
      }
    ]
  }
  ```

### 8.2 Submit Assignment Work
- **Method & Path:** `POST /api/assignments/{id}/submit`
- **Content-Type:** `multipart/form-data`
- **Form Fields:**
  - `submission_text`: `string` (notes / write-up)
  - `github_url`: `string` (GitHub repository link)
  - `file`: `File` (optional zip or document)
- **Response (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "Assignment submitted successfully",
    "submission": {
      "id": 45,
      "assignment_id": 18,
      "status": "submitted",
      "submitted_at": "2026-09-07T18:00:00Z"
    }
  }
  ```

---

## 9. Announcements (`/api/announcements`)

### 9.1 List Announcements
- **Method & Path:** `GET /api/announcements`
- **Query Parameters:**
  - `page`: `number` (default: 1)
  - `page_size`: `number` (default: 10)
  - `search`: `string`
  - `pinned`: `boolean`
  - `project_id`: `number` (optional)
- **Response (`200 OK`):**
  ```json
  {
    "page": 1,
    "total_pages": 1,
    "total": 4,
    "items": [
      {
        "id": 12,
        "title": "Welcome to Summer 2026 Internship Batch!",
        "content": "All interns please review your assigned mentor and project board.",
        "is_pinned": true,
        "author_name": "Admin Team",
        "created_at": "2026-06-01T09:00:00Z"
      }
    ]
  }
  ```

---

## 10. User Profile & Settings (`/api/profile`)

### 10.1 Get Profile
- **Method & Path:** `GET /api/profile`
- **Auth Required:** Yes
- **Response (`200 OK`):** Returns full `UserProfile` object.

### 10.2 Update Profile (Bio, Phone, Skills)
- **Method & Path:** `PUT /api/profile`
- **Request Body:**
  ```json
  {
    "bio": "Mobile Engineer specializing in high-performance Flutter applications.",
    "phone": "+91 9887679789",
    "skills": "Flutter, Dart, Provider, Bloc, REST APIs, Git"
  }
  ```
- **Response (`200 OK`):** Returns updated `UserProfile`.

### 10.3 Change Password
- **Method & Path:** `POST /api/profile/change-password`
- **Request Body:**
  ```json
  {
    "current_password": "OldPassword123!",
    "new_password": "NewSecretPassword456!",
    "confirm_password": "NewSecretPassword456!"
  }
  ```
- **Response (`200 OK`):**
  ```json
  {
    "ok": true,
    "message": "Password changed successfully"
  }
  ```

---

## 11. Notifications (`/api/notifications`)

### 11.1 List Notifications
- **Method & Path:** `GET /api/notifications?page=1`
- **Response (`200 OK`):**
  ```json
  {
    "page": 1,
    "total_pages": 1,
    "total": 3,
    "unread_count": 1,
    "notifications": [
      {
        "id": 51,
        "message": "Mentor Sarah Miller commented on your task 'Splash Screen'.",
        "link": "/projects/10",
        "is_read": false,
        "created_at": "2026-09-07T14:30:00Z"
      }
    ]
  }
  ```

### 11.2 Get Unread Notification Count
- **Method & Path:** `GET /api/notifications/unread-count`
- **Response (`200 OK`):** `{"count": 1}`

### 11.3 Mark All As Read
- **Method & Path:** `POST /api/notifications/mark-read`
- **Response (`200 OK`):** `{"ok": true}`

---

## 12. Global Search (`/api/search`)

- **Method & Path:** `GET /api/search?q={query}`
- **Auth Required:** Yes
- **Response (`200 OK`):**
  ```json
  {
    "query": "Flutter",
    "projects": [
      { "id": 10, "name": "InternHub Mobile App", "status": "in_progress" }
    ],
    "tasks": [
      { "id": 88, "title": "Build Splash Screen Animation", "status": "in_progress" }
    ],
    "users": [
      { "id": 4, "name": "Alex Johnson", "role": "intern", "email": "intern@company.com" }
    ],
    "announcements": []
  }
  ```

---

## 13. Admin & Mentor Student Management (`/api/admin/students`, `/api/mentor/students`)

For Admin and Mentor roles in the Flutter app:

| Action | Endpoint | Description |
| :--- | :--- | :--- |
| **List Students** | `GET /api/admin/students` or `GET /api/mentor/students` | Paginated students with attendance summary |
| **Search Students** | `GET /api/admin/students/search?q=name` | Live search students |
| **Students Today** | `GET /api/admin/students/today` | Real-time status (Present / Late / Absent) |
| **Student Attendance** | `GET /api/admin/students/{userId}/attendance` | Detailed 30-day attendance record for student |
| **Export Report** | `GET /api/admin/students/export?month=YYYY-MM` | Download attendance spreadsheet |

---

## 14. Ready-to-Use Flutter Dart Implementation

Here is a complete, production-ready Dart API Client using `dio` and `flutter_secure_storage`:

### 14.1 `api_client.dart`
```dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static const String _storageTokenKey = 'ih_auth_token';
  static const String _storageOrgIdKey = 'ih_org_id';

  // Base URL configuration
  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3001'; // Android Emulator
    } else {
      return 'http://127.0.0.1:3001'; // iOS Simulator / Desktop
    }
  }

  late final Dio dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    // Attach Token & Organization Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: _storageTokenKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          final orgId = await _storage.read(key: _storageOrgIdKey);
          if (orgId != null && orgId.isNotEmpty) {
            options.headers['X-Organization-Id'] = orgId;
          }

          return handler.next(options);
        },
        onError: (DioException error, handler) {
          if (error.response?.statusCode == 401) {
            // Handle token expiry - redirect to login in your app
            _storage.delete(key: _storageTokenKey);
          }
          return handler.next(error);
        },
      ),
    );
  }

  // --- Auth APIs ---

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool remember = true,
  }) async {
    final response = await dio.post(
      '/api/auth/login',
      data: {
        'email': email,
        'password': password,
        'remember': remember,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token != null) {
      await _storage.write(key: _storageTokenKey, value: token);
    }
    return data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await dio.get('/api/auth/me');
    return response.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await dio.post('/api/auth/logout');
    } finally {
      await _storage.delete(key: _storageTokenKey);
    }
  }

  // --- Attendance APIs ---

  Future<Map<String, dynamic>?> getTodayAttendance() async {
    final response = await dio.get('/api/attendance/today');
    final record = response.data['record'];
    return record != null ? (record as Map<String, dynamic>) : null;
  }

  Future<Map<String, dynamic>> checkIn({
    required File photoFile,
    required double lat,
    required double lng,
  }) async {
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(
        photoFile.path,
        filename: 'checkin.jpg',
      ),
      'lat': lat.toString(),
      'lng': lng.toString(),
    });

    final response = await dio.post(
      '/api/attendance/check-in',
      data: formData,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkOut({
    required File photoFile,
    required double lat,
    required double lng,
  }) async {
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(
        photoFile.path,
        filename: 'checkout.jpg',
      ),
      'lat': lat.toString(),
      'lng': lng.toString(),
    });

    final response = await dio.post(
      '/api/attendance/check-out',
      data: formData,
    );
    return response.data as Map<String, dynamic>;
  }

  // --- Projects & Tasks APIs ---

  Future<List<dynamic>> getProjects({String? search, String? status}) async {
    final queryParams = <String, dynamic>{};
    if (search != null) queryParams['search'] = search;
    if (status != null) queryParams['status'] = status;

    final response = await dio.get(
      '/api/projects',
      queryParameters: queryParams,
    );
    return response.data['projects'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateTaskStatus({
    required int taskId,
    required String status,
  }) async {
    final response = await dio.put(
      '/api/projects/tasks/$taskId',
      data: {'status': status},
    );
    return response.data as Map<String, dynamic>;
  }

  // --- Leave APIs ---

  Future<Map<String, dynamic>> getMyLeave() async {
    final response = await dio.get('/api/leave/mine');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestLeave({
    required String startDate,
    required String endDate,
    required String reason,
    String leaveType = 'casual',
    File? attachment,
  }) async {
    if (attachment != null) {
      final formData = FormData.fromMap({
        'start_date': startDate,
        'end_date': endDate,
        'reason': reason,
        'leave_type': leaveType,
        'attachment': await MultipartFile.fromFile(attachment.path),
      });
      final response = await dio.post('/api/leave', data: formData);
      return response.data as Map<String, dynamic>;
    } else {
      final response = await dio.post(
        '/api/leave',
        data: {
          'start_date': startDate,
          'end_date': endDate,
          'reason': reason,
          'leave_type': leaveType,
        },
      );
      return response.data as Map<String, dynamic>;
    }
  }

  // --- Daily Standup ---

  Future<Map<String, dynamic>> submitStandup({
    required String date,
    required String did,
    required String plan,
    String? blockers,
    String? mood,
  }) async {
    final response = await dio.post(
      '/api/standup',
      data: {
        'date': date,
        'did': did,
        'plan': plan,
        'blockers': blockers,
        'mood': mood,
      },
    );
    return response.data as Map<String, dynamic>;
  }
}
```

---

## 15. Summary of Endpoints Quick Reference Table

| Module | Method | Endpoint | Description |
| :--- | :--- | :--- | :--- |
| **Auth** | `POST` | `/api/auth/login` | Log in and receive Bearer token |
| **Auth** | `GET` | `/api/auth/me` | Fetch active user session |
| **Auth** | `POST` | `/api/auth/logout` | End session |
| **Auth** | `POST` | `/api/auth/register` | Public registration |
| **Dashboard** | `GET` | `/api/intern/dashboard` | Today check-in status, tasks, projects |
| **Dashboard** | `GET` | `/api/mentor/dashboard` | Supervised interns, pending approvals |
| **Dashboard** | `GET` | `/api/admin/dashboard` | Platform metrics & charts |
| **Attendance** | `GET` | `/api/attendance/today` | Today's check-in / check-out status |
| **Attendance** | `POST` | `/api/attendance/check-in` | Upload selfie photo + GPS coordinates |
| **Attendance** | `POST` | `/api/attendance/check-out` | Upload checkout selfie + GPS coordinates |
| **Attendance** | `GET` | `/api/attendance/history` | Monthly calendar attendance records |
| **Attendance** | `GET` | `/api/attendance/{id}/photo/{kind}` | Download check-in/out selfie photo |
| **Projects** | `GET` | `/api/projects` | List active projects |
| **Projects** | `GET` | `/api/projects/{id}` | Project board with Kanban tasks & members |
| **Projects** | `POST` | `/api/projects` | Create new project |
| **Tasks** | `POST` | `/api/projects/{projectId}/tasks` | Create task in project |
| **Tasks** | `PUT` | `/api/projects/tasks/{taskId}` | Update task status, priority, or assignee |
| **Tasks** | `POST` | `/api/projects/tasks/{taskId}/comments` | Post comment (with optional file) |
| **Leave** | `GET` | `/api/leave/mine` | Leave history & remaining quota |
| **Leave** | `POST` | `/api/leave` | Apply for leave (with optional proof) |
| **Leave** | `POST` | `/api/leave/{id}/review` | Approve/reject leave request |
| **Standup** | `GET` | `/api/standup/today` | Today's standup entry |
| **Standup** | `POST` | `/api/standup` | Submit daily standup log |
| **Assignments** | `GET` | `/api/assignments` | List homework/course assignments |
| **Assignments** | `POST` | `/api/assignments/{id}/submit` | Submit work (text, GitHub URL, file) |
| **Profile** | `GET` | `/api/profile` | Current user profile |
| **Profile** | `PUT` | `/api/profile` | Update bio, phone number, and skills |
| **Profile** | `POST` | `/api/profile/change-password` | Update user password |
| **Notifications** | `GET` | `/api/notifications` | List user notifications |
| **Notifications** | `POST` | `/api/notifications/mark-read` | Mark all notifications as read |
| **Search** | `GET` | `/api/search?q={query}` | Search projects, tasks, interns, mentors |

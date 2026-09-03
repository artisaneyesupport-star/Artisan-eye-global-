# ArtisanEye Backend — Complete API

Node.js · Express · PostgreSQL · Prisma · Socket.io · Paystack · Cloudinary · Nodemailer

---

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Copy env template and fill in values
cp .env.example .env

# 3. Create PostgreSQL database
psql -U postgres -c "CREATE DATABASE artisaneye;"

# 4. Run migrations
npm run db:migrate

# 5. Seed test data
npm run db:seed

# 6. Start dev server
npm run dev
# → API:    http://localhost:4000
# → Socket: ws://localhost:4000
```

---

## Project Structure

```
artisaneye-backend/
├── prisma/
│   ├── schema.prisma         # All models + enums
│   └── seed.js               # Test data (admin, client, 8 artisans, jobs, messages)
├── src/
│   ├── config/
│   │   ├── prisma.js         # Prisma client singleton
│   │   ├── socket.js         # Socket.io server + auth middleware
│   │   └── cron.js           # Nightly cleanup jobs
│   ├── controllers/
│   │   ├── auth.controller.js
│   │   ├── artisan.controller.js
│   │   ├── job.controller.js
│   │   ├── message.controller.js
│   │   ├── payment.controller.js
│   │   ├── email.controller.js
│   │   └── admin.controller.js
│   ├── middleware/
│   │   ├── auth.js            # JWT authenticate + requireRole
│   │   ├── validate.js        # express-validator wrapper
│   │   ├── sanitize.js        # XSS — strips HTML from all req.body fields
│   │   ├── userRateLimit.js   # Per-user rate limiting (keyed to user ID)
│   │   ├── security.js        # HTTPS redirect + security headers
│   │   ├── upload.js          # Legacy (replaced by cloudinary.js)
│   │   └── errorHandler.js    # Global error handler
│   ├── routes/
│   │   ├── auth.routes.js
│   │   ├── artisan.routes.js
│   │   ├── job.routes.js
│   │   ├── message.routes.js
│   │   ├── payment.routes.js
│   │   ├── email.routes.js
│   │   ├── admin.routes.js
│   │   └── contact.routes.js
│   ├── utils/
│   │   ├── jwt.js             # Sign/verify access + refresh tokens
│   │   ├── response.js        # Consistent API response helpers
│   │   ├── mailer.js          # Nodemailer + 8 branded email templates
│   │   ├── paystack.js        # Paystack API wrapper
│   │   └── cloudinary.js      # Cloudinary upload/delete + multer memoryStorage
│   ├── app.js                 # Express app (all routes, middleware)
│   └── index.js               # HTTP server entry point
├── frontend-auth.js           # Drop-in frontend auth client
├── frontend-messaging.js      # Drop-in frontend messaging + Socket.io client
├── frontend-billing.js        # Drop-in frontend billing client
├── billing-success.html       # Paystack callback page
├── verify-email.html          # Email verification callback page
├── reset-password.html        # Password reset page
├── .env.example
└── package.json
```

---

## Environment Variables

```env
# Database
DATABASE_URL="postgresql://postgres:password@localhost:5432/artisaneye"

# JWT
JWT_ACCESS_SECRET="<64 char hex>"
JWT_REFRESH_SECRET="<64 char hex>"
JWT_ACCESS_EXPIRES_IN="15m"
JWT_REFRESH_EXPIRES_IN="7d"

# Server
PORT=4000
NODE_ENV=development
FRONTEND_URL="http://localhost:3000"

# Cloudinary (photo uploads)
CLOUDINARY_CLOUD_NAME="your_cloud_name"
CLOUDINARY_API_KEY="your_api_key"
CLOUDINARY_API_SECRET="your_api_secret"

# Paystack
PAYSTACK_SECRET_KEY="sk_test_xxx"
PAYSTACK_PUBLIC_KEY="pk_test_xxx"
PAYSTACK_WEBHOOK_SECRET="your_webhook_secret"
PAYSTACK_PLAN_PRO="PLN_xxx"
PAYSTACK_PLAN_TEAM="PLN_xxx"
PAYMENT_CALLBACK_URL="http://localhost:3000/billing-success.html"

# Email (leave blank for Ethereal auto-account in dev)
SMTP_HOST="smtp.ethereal.email"
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=""
SMTP_PASS=""
EMAIL_FROM="ArtisanEye <noreply@artisaneye.com>"
SUPPORT_EMAIL="support@artisaneye.com"
APP_URL="http://localhost:3000"
```

---

## API Reference

### Base URL: `http://localhost:4000/api`

All responses follow the shape:
```json
{ "success": true|false, "message": "...", "data": {} }
```

---

### Auth — `/api/auth`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/register` | Public | Create account. Body: `{ fullName, email, password, role?, phone? }` |
| POST | `/login` | Public | Login. Body: `{ email, password }` |
| POST | `/refresh` | Cookie | Silent token refresh |
| POST | `/logout` | Public | Revoke refresh token |
| GET | `/me` | Required | Current user profile |

---

### Artisans — `/api/artisans`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/` | Public | Search artisans. Query: `trade, city, verified, minRating, plan, search, sortBy, page, limit` |
| GET | `/me` | ARTISAN | Own profile |
| PATCH | `/me` | ARTISAN | Update profile. Body: `{ trade, city, bio, yearsExperience, startingRate, languages, serviceArea }` |
| POST | `/me/photos` | ARTISAN | Upload photos to Cloudinary. `multipart/form-data`, field: `photos` |
| DELETE | `/me/photos/:photoId` | ARTISAN | Delete photo (removes from Cloudinary) |
| GET | `/:id` | Public | Public artisan profile with photos + reviews |

---

### Jobs — `/api/jobs`

The core booking flow. Reviews are locked to CONFIRMED jobs only.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/` | CLIENT | Create job request. Body: `{ artisanUserId, title, description, agreedPrice?, scheduledAt? }` |
| GET | `/` | Required | List own jobs. Query: `status, page, limit` |
| GET | `/:id` | Participant | Get single job |
| PATCH | `/:id/status` | Participant | Transition status. Body: `{ status, cancelReason? }` |
| POST | `/:id/review` | CLIENT | Leave review (CONFIRMED jobs only). Body: `{ rating, comment? }` |

**Job state machine:**

```
PENDING
  ├── ARTISAN → ACCEPTED
  └── either → CANCELLED

ACCEPTED
  ├── ARTISAN → IN_PROGRESS
  └── either → CANCELLED

IN_PROGRESS
  ├── ARTISAN → COMPLETED
  └── CLIENT  → DISPUTED

COMPLETED
  ├── CLIENT → CONFIRMED  ← review unlocked here
  └── CLIENT → DISPUTED

CONFIRMED  (terminal)
CANCELLED  (terminal)
DISPUTED   → admin resolves → CONFIRMED or CANCELLED
```

---

### Messaging — `/api/messages`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/threads` | CLIENT | Start thread. Body: `{ artisanUserId }` |
| GET | `/threads` | Required | List all threads + unread counts |
| GET | `/threads/:id` | Participant | Thread + paginated messages |
| POST | `/threads/:id` | Participant | Send message. Body: `{ body }` |
| PATCH | `/threads/:id/read` | Participant | Mark messages as read |
| DELETE | `/threads/:id/messages/:msgId` | Sender | Redact message (10 min window) |

**Socket.io events:**

| Direction | Event | Payload |
|-----------|-------|---------|
| Client → Server | `thread:join` | `{ threadId }` |
| Client → Server | `thread:leave` | `{ threadId }` |
| Client → Server | `thread:typing` | `{ threadId }` |
| Server → Client | `message:new` | Full message object |
| Server → Client | `message:deleted` | `{ messageId, threadId }` |
| Server → Client | `messages:read` | `{ threadId, readBy }` |
| Server → Client | `user:typing` | `{ threadId, userId, fullName }` |

---

### Payments — `/api/payments`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/initialize` | ARTISAN | Start Paystack checkout. Body: `{ plan: "PRO"\|"TEAM" }` |
| GET | `/verify/:reference` | ARTISAN | Verify payment after redirect |
| GET | `/subscription` | ARTISAN | Current plan + subscription status |
| POST | `/cancel` | ARTISAN | Cancel subscription. Body: `{ emailToken }` |
| POST | `/webhook` | Paystack | Webhook receiver (signature verified) |

**Payment flow:**
```
POST /initialize → redirect to authorizationUrl → Paystack → callback URL
→ GET /verify/:reference → plan upgraded in DB
(Paystack also fires webhook as backup confirmation)
```

---

### Email — `/api/email`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/send-verification` | Required | Resend verification email |
| GET | `/verify?token=xxx` | Public | Verify email from link |
| POST | `/forgot-password` | Public | Request reset link. Body: `{ email }` |
| POST | `/reset-password` | Public | Set new password. Body: `{ token, password }` |

**Emails sent automatically:**
- Register → verification email
- Verify → welcome email
- Message received (offline) → notification email
- Payment confirmed → receipt
- Subscription cancelled → cancellation notice
- Artisan verification approved/rejected → status email

**Dev mode:** Emails auto-use an Ethereal test inbox. Preview URL logged to console.

---

### Admin — `/api/admin` (ADMIN role required)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/stats` | Platform stats: users, jobs, revenue |
| GET | `/users` | List users. Query: `role, search, page, limit` |
| GET | `/verification-queue` | Artisans pending verification (oldest first) |
| PATCH | `/verification/:profileId/approve` | Approve + email artisan |
| PATCH | `/verification/:profileId/reject` | Reject + email artisan. Body: `{ reason? }` |
| PATCH | `/jobs/:id/resolve-dispute` | Resolve disputed job. Body: `{ resolution, outcome }` |

**To create an admin:**
```sql
UPDATE users SET role = 'ADMIN' WHERE email = 'admin@artisaneye.com';
```
Or use the seeded `admin@artisaneye.com` / `Password123!` account.

---

### Contact — `/api/contact`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/` | Public | Send contact form. Body: `{ name, email, subject, message, reason? }` |

Sends email to `SUPPORT_EMAIL` + auto-reply to sender.

---

## Security Features

| Feature | Implementation |
|---------|---------------|
| XSS protection | `sanitize.js` strips HTML from all `req.body` fields globally |
| SQL injection | Prisma parameterized queries (no raw SQL) |
| Auth | JWT access tokens (15m) + HttpOnly refresh cookie (7d) with rotation |
| Rate limiting | Global (300/15min) + per-user (keyed to user ID, configurable per route) |
| HTTPS | `httpsRedirect` middleware forces HTTPS in production |
| HSTS | 1-year Strict-Transport-Security header in production |
| Helmet | Standard security headers on all responses |
| Password hashing | bcrypt, cost factor 12 |
| Webhook verification | HMAC-SHA512 signature check on all Paystack webhooks |

---

## Background Jobs (node-cron)

Runs automatically on server start:

| Time | Task |
|------|------|
| 02:00 nightly | Purge expired/revoked refresh tokens |
| 02:15 nightly | Purge used/expired email + password reset tokens |
| 02:30 nightly | Downgrade artisans with expired subscriptions to STARTER |

---

## Test Accounts (after `npm run db:seed`)

All accounts use password: **`Password123!`**

| Email | Role | Notes |
|-------|------|-------|
| `admin@artisaneye.com` | ADMIN | Can access verification queue, stats, dispute resolution |
| `client@test.com` | CLIENT | Has 5 jobs in various states |
| `chidi@test.com` | ARTISAN | Verified, Pro plan, confirmed job with review |
| `aisha@test.com` | ARTISAN | Verified, confirmed job with review |
| `ibrahim@test.com` | ARTISAN | Pending verification (shows in admin queue) |
| `grace@test.com` | ARTISAN | Unverified |
| `folake@test.com` | ARTISAN | Verified, Pro, pending job |
| `blessing@test.com` | ARTISAN | Verified, Pro, job in progress |

---

## Frontend Integration

Three drop-in JS clients (copy to your site folder):

```html
<!-- Auth (login, register, logout) -->
<script src="frontend-auth.js"></script>

<!-- Messaging + Socket.io -->
<script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
<script src="frontend-messaging.js"></script>

<!-- Billing (Paystack checkout, subscription status) -->
<script src="frontend-billing.js"></script>
```

Three callback pages (copy to your site folder):
- `verify-email.html` — email verification
- `reset-password.html` — password reset
- `billing-success.html` — payment confirmation

---

## Health Check

```
GET http://localhost:4000/health
→ { "status": "ok", "timestamp": "...", "env": "development" }
```

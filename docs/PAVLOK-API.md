# Pavlok account API (`api.pavlok.com/api/v5`)

Recovered from the Android app (see `RE-FINDINGS.md`) and then **verified
live** against a real account on 2026-08-29. Every shape below was observed in
an actual response unless marked otherwise.

Used by Jolt's optional *Pavlok account* section: sign in with a Pavlok
account to poke Pavlok friends from Jolt. See "Receiving pokes" for the one
thing this cannot do.

> Not affiliated with Pavlok Inc. This talks to a first-party API on behalf of
> the account holder, with their credentials, at their request.

## Auth

```
POST /users/login
{"user": {"email": "...", "password": "..."}}
```

The credentials are **nested under `user`** — a flat `{email,password}` body is
rejected with `422 {"errors":[{"loc":["body","user"],"msg":"field required"}]}`.

`200` returns `{"user": { …profile…, "id": 123456, "token": "<JWT>" }}`. The
token is inside `user`, not at the top level, and there is no
`Authorization`/`Set-Cookie` header on the response.

Every other call takes:

```
Authorization: Bearer <token>
```

Other auth paths seen in the binary (not exercised): `/users/`,
`/users/forget-password`, `/users/reset-password`, `/user/change-password`,
`/social/auth-providers`.

## Friends

| Endpoint | Response |
|---|---|
| `GET /friendships/get-friends` | `{"users":[{id, username, firstName, lastName, profilePictureUrl}]}` |
| `GET /friendships/received-requests` | `{"friendshipRequests":[{id, requesterId, addresseeId, status, createdAt, user{…}}]}` |
| `POST /friendships/` | send request (body `{addresseeId}`) |
| `POST /friendships/accept-request` / `reject-request` / `cancel-request` | `{requesterId}` / `{addresseeId}` |
| `POST /friendships/remove-friend` | `{userId}` |
| `GET /users/search?query=` | user lookup |
| `GET /users/get-user-by-id?user_id=` | single user |
| `GET /users/friends-suggestions` | suggestions |

`status` observed: `ACCEPTED`.

## Poke permissions

| Endpoint | Meaning |
|---|---|
| `GET /poke-permissions/` | what **I grant** my friends |
| `GET /poke-permissions/received` | what **they grant me** — gates what I may send |

Both return `{"pokePermissions":[…]}` with:

```
{ id, userId, friendId, canVibrate, canChime, canZap, maxZapValue,
  createdAt, updatedAt, deletedAt, friend: { id, firstName, lastName, … } }
```

`canChime` is the beep/piezo permission. `maxZapValue` is 0…100 and caps zap
intensity. Create/update/delete via `POST`/`PUT`/`DELETE` on
`/poke-permissions/`.

## Sending a poke

```
POST /pokes/send/user/{userId}
```

with a `stimulus` object in the body (field name confirmed in
`friends_api.dart`; the exact stimulus JSON was **not** exercised, because
firing one zaps a real person). Send only what
`/poke-permissions/received` allows for that friend, and clamp zap intensity to
`maxZapValue`.

## Devices and the stimulus journal

```
GET /user-devices/        -> {"devices":[{id, macAddress, name}]}
GET /diagnostic_logs/?mac_address=<MAC>&page=&page_size=&types=Zap&types=Beep&types=Vibe
                          -> {"items":[…], "count", "page", "pageSize"}
```

`mac_address` is **required** (422 without it) and is the bare hex form with no
separators, e.g. `3E95A490E11D`, exactly as `/user-devices/` reports it.

Journal entries look like:

```
{ id, sectorId, userId, macAddr, firmwareVersion, name: "Vibe"|"Beep"|"Zap",
  inode, offset, ts, tz, type, parsedJson }
```

## Notifications

```
GET /notifications/?page=&page_size=   -> {"items":[…], "count", "page", "pageSize"}
GET /notifications/new/?timestamp=<YYYY-MM-DDTHH:MM:SS>  -> {"notifications":[…]}
GET /notifications/get-one/{id}
POST /notifications/mark-all-read
```

The delta endpoint rejects an offset or `Z` suffix —
`422 {"errors":["Timestamp must be without timezone"]}`. Pass a naive local
timestamp.

Notification fields: `id, userId, title, content, read, readAt, opened,
openedAt, icon, sourceId, sourceType, url, urlType, category, data,
campaignId, createdAt, …`.

**Categories that actually exist** (all 362 notifications on the test account,
cross-checked against the categories the app's own code knows):

```
achievement_badge   volts_assignment   review_request
friendship          friendship_request
poke_permission     poke_permission_updated
```

## Receiving pokes — not possible through this API

This is the load-bearing limitation, established by exhaustion rather than
assumption:

1. **No poke-received notification exists.** Not in 362 notifications on a
   real account, and not among the categories the official app can render.
   `poke_permission` / `poke_permission_updated` are about *permission* changes,
   not pokes.
2. **No poke history endpoint.** `/pokes/`, `/pokes/received`, `/pokes/sent`,
   `/pokes/history`, `/pokes/me`, `/pokes/list` all `404`.
3. **The stimulus journal has no sender.** `/diagnostic_logs/` is the *device's*
   own log uploaded after the fact — it records that a Vibe/Beep/Zap fired, not
   who caused it, so a friend's poke is indistinguishable from a button press,
   and it only appears once the device syncs.
4. An incoming poke reaches the official app **only as a Firebase Cloud
   Messaging push** (it registers its FCM token at `POST /phone-devices/`).
   Receiving those in Jolt would mean impersonating Pavlok's Firebase app with
   their project credentials. Out of the question.

So Jolt can **send** pokes to Pavlok friends, and can show a **best-effort,
unattributed** "your device fired a stimulus" feed from the journal — but it
cannot say "Alice poked you". The UI must not imply otherwise.

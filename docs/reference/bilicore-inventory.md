# BiliCore inventory (`D:\Repos\Apps\BiliNative\ios\Packages\BiliCore`) for the Dart port

Snapshot of BiliNative `main` at `a956b99` (2026-10-17), read-only. File tables give file names inside the folder named in their heading. Line counts come from `wc -l`, test counts from `grep -c 'func test'`.

---

## 1. Package layout

**`D:\Repos\Apps\BiliNative\ios\Packages\BiliCore\Package.swift`**
- `swift-tools-version:6.0`, `swiftLanguageModes: [.v5]`, platforms `.iOS("26.0")` and `.macOS("15.0")`. No third-party dependencies.
- Products:
  - library `BiliCore`, made of targets `BiliShared, DevLog, BiliAPI, DashHLS, Ripper, LocalHTTP, AppLogic, Danmaku`.
  - executable `ripper-bench`.
- Targets and their dependencies:
  - `BiliShared`: none.
  - `DevLog`: BiliShared.
  - `Danmaku`: BiliShared.
  - `BiliAPI`: BiliShared, DevLog, Danmaku.
  - `DashHLS`: BiliShared.
  - `Ripper`: BiliShared, DevLog. Excludes `LICENSE-BTR.txt`.
  - `LocalHTTP`: BiliShared.
  - `AppLogic`: BiliShared, BiliAPI.
  - `ripper-bench` (executableTarget): BiliShared, BiliAPI, DashHLS, Ripper, DevLog.
- Test targets: `BiliSharedTests`, `DevLogTests`, `DanmakuTests`, `BiliAPITests`, `DashHLSTests`, `RipperTests`, `LocalHTTPTests`, `AppLogicTests`. Each depends on its target plus that target's dependencies.

**Sources, 7,877 Swift lines in total** (plus the 24-line `LICENSE-BTR.txt`).

| Folder (under `...\BiliCore\Sources\`) | Files (lines) | Total |
|---|---|---|
| `AppLogic` | Autoplay 47, CountFormat 15, GestureMath 27, HeartbeatSchedule 31, HistoryGrouping 36, QualityNames 45, QualityRules 10, ResumePoint 10, TimeFormat 44 | 265 |
| `BiliAPI` | ActionModels 152, AppSigner 21, BiliClient+Actions 101, BiliClient+App 73, BiliClient+Comments 75, BiliClient+Danmaku 98, BiliClient+Feed 61, BiliClient+Video 57, BiliClient 236, BiliError 35, BiliHosts 11, CommentModels 356, CookieJar 64, FeedModels 158, FormEncoding 9, HTTP 105, LinkParser 43, MD5 86, Models 258, RichText 203, TrackSelector 64, VideoModels 373, WBI 45 | 2,684 |
| `BiliShared` | ByteRange 66, Locked 19, MediaSegment 16, MonotonicClock 32 | 133 |
| `Danmaku` | DanmakuElem 64, DanmakuFilter 180, DanmakuSegment 47, DanmakuTimeline 47, LaneLayout 77, MidHash 18, ProtobufReader 62 | 495 |
| `DashHLS` | BoxReader 53, CodecMapper 39, InitSegmentFixer 95, PlaylistBuilder 82, SidxParser 59 | 328 |
| `DevLog` | FileSink 160, LogEvent 77, Logger 52, MemorySink 13, NetworkSink 123, Redactor 142, Replay 60 | 627 |
| `LocalHTTP` | HTTPRequestParser 52, HTTPResponseWriter 22, PlaybackRouter 150, RangeRequest 37 | 261 |
| `Ripper` | Attempt 245, AutoConcurrency 275, BanList 157, ConnectionPool 157, EngineStats 80, HurryPlacement 62, Meter 41, NodeCatalog 145, NodeStats 147, PieceDownloader 290, PrimaryAssigner 81, RangeDownloader 140, Resolver 301, RipperConfig 22, RipperSession 482, Transport 50, URLSessionRangeTransport 137, LICENSE-BTR.txt 24 | 2,812 Swift (2,836 with the licence) |
| `ripper-bench` | Bench 272 | 272 |

Tests total 8,247 lines and 546 tests. Per-file detail is in section 7.

---

## 2. Modules

- **BiliShared**: small shared pieces.
  - `ByteRange`: inclusive range. `parse("a-b")`, `headerValue`, and `split(concurrency:minChunk:)`, which is BTR `splitRange`: at most `min(512, concurrency)` pieces, each at least `max(32 KiB, minChunk)`, sizes differing by at most 1 byte.
  - `ContentRange.parse` reads `bytes a-b/total` or `bytes a-b/*`.
  - `Locked<T>` (an NSLock box), `MediaSegment(index, range, startTime, duration)`, `MonotonicClock` (systemUptime in ms), `ManualClock`, `sleepMs`.
- **DevLog**: structured logging. `Logger.shared` takes sinks: `FileSink`, `NetworkSink`, `MemorySink`. `Redactor` scrubs secrets. `AckStore` and `ReplayPlanner` resend events the PC never confirmed. Depends on BiliShared.
- **Danmaku**: a hand-written protobuf reader, the `DanmakuElem`/`DanmakuSegment` decoders, `DanmakuSegments` (6-minute indexing), `DanmakuFilter` (type, colour and rule blocks, dedupe), `DanmakuTimeline` (emits each item once as the playhead passes), `LaneLayout` (collision-free lanes) and `MidHash` (CRC-32 of the uid). Depends on BiliShared.
- **BiliAPI**: the web and app API client.
  - `BiliClient` handles WBI signing, csrf, cookies, the 412 retry and envelope decoding. It runs over the `HTTPTransport` protocol; the real one is `URLSessionHTTPTransport`.
  - Other types: `CookieJar`, `AppSigner`, all models, `RichText` (comment runs), `LinkParser` (BV/av/b23.tv), `TrackSelector` (quality and codec choice) and a hand-written `MD5`.
  - Depends on BiliShared, DevLog and Danmaku.
- **DashHLS**: MP4 box reading, SIDX parsing, the `hev1`→`hvc1` init rewrite, codec-string mapping and HLS playlist text. Depends on BiliShared.
- **Ripper**: the BTR engine port. `RipperSession` is the public entry point. It uses `Resolver`, `BanList`, `NodeCatalog`, `ConnectionPool`, `AutoConcurrency`, `RangeDownloader`, `PieceDownloader`, `AttemptRunner`, `NodeStats`, `HurryPlacement`, `PrimaryAssigner`, `Meter` and `EngineStats`, and talks to the network through the `RangeTransport` protocol. Depends on BiliShared and DevLog.
- **LocalHTTP**: pure pieces of the localhost HLS server: HTTP head parser, response-head writer, Range parser and `PlaybackRouter` (token/name → playlist text or a media byte stream). The socket listener itself is in the app (`ios\Sources\App\Playback\LocalServer.swift`). Depends on BiliShared.
- **AppLogic**: pure UI and playback rules (section 9). Depends on BiliAPI (`HistoryItem`).
- **ripper-bench**: CLI speed test.
  - Flags: `--bv`, `--playurl`, `--cookies`, `--mb`, `--mode`, `--quality`, `--codec`, `--seeks N`, `--no-hurry`.
  - Default run compares one connection against Ripper.
  - `--seeks N` times N cold 4 MiB reads at seeded random offsets (seed 17), each through a new session.

---

## 3. Every Bilibili HTTP endpoint the package calls

### How requests are built
All in `D:\Repos\Apps\BiliNative\ios\Packages\BiliCore\Sources\BiliAPI\BiliClient.swift`.

- **Hosts**:
  - `api = https://api.bilibili.com`
  - `passport = https://passport.bilibili.com`
  - `appAPI = https://app.bilibili.com`
  - `https://account.bilibili.com` (coin balance only)
- **Headers**:
  - `User-Agent`: a macOS Safari string (`...Version/26.0 Safari/605.1.15`).
  - `Referer`: `https://www.bilibili.com/` unless the call overrides it.
  - `Accept`: `application/json`, or `*/*` for `getData`.
- **Cookie header**: only for hosts where `BiliHosts.isBilibili` holds (exact `bilibili.com` or `*.bilibili.com`). `CookieJar.headerValue` sorts names with SESSDATA first.
- **POST (web)**:
  - Body is `application/x-www-form-urlencoded; charset=UTF-8`, encoded like encodeURIComponent (space = `%20`, keys sorted).
  - `csrf=<bili_jct>` is added and overrides any caller value; `Origin: https://www.bilibili.com` is set.
  - Without `bili_jct`, it throws `.api(-101, "账号未登录")` before sending.
  - A form POST to a non-Bilibili host is refused.
- **Cookie-less mode** (`cookies: false`, used by the app API): no Cookie header, no csrf, no 412 retry.
- **WBI signing** (`WBI.swift`):
  - The mixin key comes from the `nav` `wbi_img.img_url` and `sub_url` file names, permuted by the 64-entry table and cut to 32 chars.
  - It is cached per UTC day (`unixSeconds/86400`). An empty key throws instead of signing.
  - Signing strips `!'()*` from values, adds `wts=<unix s>`, sorts and encodes, then appends `&w_rid=md5(query+mixin)`. Unsigned queries are sorted and encoded the same way.
- **App signing** (`AppSigner.swift`): fields plus `appkey` and `ts`, then `sign = md5(sortedEncodedQuery + appSecret)`. The key pair is passed in by the app, from the `BILI_APP_KEYS` secret → `ios/Generated/AppKeys.swift`.
- **Risk control**: an HTTP 412 (not on the spi path, not cookie-less) removes `buvid3`/`buvid4`, calls `ensureRiskCookies()` and retries once.
- **Envelope**: `BiliEnvelope<T>{code, message, data}`. Data is decoded strictly only when `code == 0`.
- **Transport** (`HTTP.swift`): `URLSessionHTTPTransport` uses an ephemeral session, no URLSession cookie store, 15 s request timeout. A redirect to a non-Bilibili host strips the Cookie header and the body.
- **Errors** (`BiliError.swift`): `http(Int)`, `api(code,message)`, `decoding`, `notDash`, `invalidLink`. Chinese `userMessage` strings: -101 需要登录; -352/-412 请求过于频繁; -404/62002/62004 视频不存在.

### Endpoint table
Signing column: **W** = WBI w_rid, **C** = csrf (bili_jct) form, **A** = app key + sign, **–** = none (cookies still sent).

| Endpoint | Method | Params | Sign | Swift function (file) | Response model |
|---|---|---|---|---|---|
| `/x/web-interface/nav` | GET | – | – | `nav()` (BiliClient) | `NavInfo` (isLogin, mid, uname, face, vipStatus, vipType, wbi img/sub URL). A -101 reply is still returned. |
| `/x/frontend/finger/spi` | GET | – | – | `ensureRiskCookies()` (BiliClient), only when buvid3 or buvid4 is missing | `SPIInfo{b_3,b_4}` → cookies `buvid3`/`buvid4` |
| `/x/web-interface/view` | GET | `bvid` or `aid` | – | `view(bvid:)`, `view(aid:)`, `resolve(_:)` (BiliClient) | `VideoView` (bvid, aid, title, owner.name, pages[cid,page,part,duration]) |
| b23.tv / bili2233.cn short link | GET (over https) | – | – | `resolve(.short)`: follows redirects, re-parses `finalURL` | – |
| `/x/player/wbi/playurl` | GET | `bvid, cid, qn, fnval=4048, fnver=0, fourk=1` | W | `playURL(bvid:cid:quality:)` (BiliClient) | `PlayURLInfo` (quality, accept_quality/description, `Dash{duration, video[], audio[]}` of `DashStream`, hasDurl, last_play_time, last_play_cid). Throws `notDash` when there is no dash. |
| `/x/web-interface/wbi/view` | GET | `bvid` | W | `videoDetail(bvid:)` (+Video) | `VideoDetail` (desc_v2 mentions, stat, owner, pages, `ugc_season` → `UgcSeason/SeasonSection/SeasonEpisode` = 合集, staff, dimension with rotate swap, honor_reply, redirect_url) |
| `/x/player/wbi/v2` | GET | `bvid, cid` | W | `playerInfo(bvid:cid:)` | `PlayerInfo` (last_play_cid, chapters from `view_points` only when type 2) |
| `/x/player/online/total` | GET | `aid, bvid, cid` | – | `onlineCount(...)` | `data.total` display string |
| `/x/web-interface/archive/related` | GET | `bvid` | – | `related(bvid:)` | `[VideoCard]`; items with a `redirect_url` are dropped |
| `/x/click-interface/web/heartbeat` | POST | `bvid, cid, type=3, played_time` (Referer = video page) | C | `heartbeat(bvid:cid:playedTime:)` | none |
| `/x/v2/history/toview/add` (稍后再看) | POST | `aid` | C | `addToWatchLater(aid:)` | none |
| `/x/web-interface/wbi/index/top/feed/rcmd` | GET | `fresh_type=4, ps=12, fresh_idx=i, fresh_idx_1h=i, brush=i, feed_version=V8` | W | `recommendFeed(index:)` (+Feed) | `item[]`, keeping only `goto=="av"` → `FeedCard` (id/aid, bvid, cid, title, pic, duration, stat, owner, rcmd_reason.content, dimension) |
| `/x/web-interface/history/cursor` | GET | `max, view_at, business=archive, type=archive, ps=20` | – | `history(after:)` | `HistoryPage{items:[HistoryItem], next:HistoryCursor?}`. A zero cursor or empty list means the end. |
| `/x/web-interface/archive/relation` | GET | `aid, bvid` | – | `relation(aid:bvid:)` (+Actions) | `VideoRelation` (like, dislike, favorite, attention, coin 0-2) |
| `/x/web-interface/card` | GET | `mid, photo=false` | – | `uploaderCard(mid:)` | `UploaderCard` (card.mid as string, name, face, vip.status, follower, archive_count, following) |
| `/x/web-interface/archive/like` | POST | `aid, like=1/2` (Referer = video page) | C | `like(aid:bvid:on:)` | none |
| `/x/web-interface/archive/like/triple` (三连) | POST | `aid, eab_x=2, ramval=0, source=web_normal, ga=1, spmid=333.788.0.0, statistics={"appId":100,"platform":5}` | C | `triple(aid:bvid:)` | `TripleResult` (like, coin, fav, multiply) |
| `/x/web-interface/coin/add` | POST | `aid, multiply, select_like=1/0` | C | `coin(aid:bvid:multiply:alsoLike:)` | none |
| `account.bilibili.com/site/getCoin` | GET | – | – | `coinBalance()` | `money` (Double) |
| `/x/v3/fav/folder/created/list-all` | GET | `up_mid, rid=aid, type=2` | – | `favouriteFolders(mid:aid:)` | `list[]` → `FavFolder` (id, title, media_count, attr bit0 = private, bit1 clear = default, fav_state) |
| `/x/v3/fav/resource/batch-deal` | POST | `rid, type=2, resources="aid:2", add_media_ids, del_media_ids` (comma lists) | C | `updateFavourites(aid:add:remove:)` | none |
| `/x/v3/fav/folder/add` | POST | `title, privacy=1/0` | C | `createFolder(title:isPrivate:)` | `FavFolder` |
| `/x/web-interface/share/add` | POST | `aid` | C | `countShare(aid:)` | none |
| `/x/relation/modify` (关注) | POST | `fid, act=1/2, re_src=14` (Referer `https://space.bilibili.com/{mid}`) | C | `follow(mid:on:)` | none |
| `/x/web-interface/view/detail/tag` | GET | `bvid, cid` | – | `tags(bvid:cid:)` | `[VideoTag]` (tag_id, tag_name, tag_type normal/topic/bgm) |
| `/x/v2/reply/wbi/main` | GET | `oid=aid, type=1, mode` (3 hot / 2 time), `pagination_str={"offset":"…"}` | W | `comments(aid:sort:offset:)` (+Comments) | `CommentListData` → `CommentPage` (replies, top_replies pinned on page 1 only, cursor.pagination_reply.next_offset, is_end, all_count) |
| `/x/v2/reply/main` | GET | same | – | fallback in `comments` on api -352/-403 or HTTP 412 | same |
| `/x/v2/reply/reply` (评论详情) | GET | `oid, type=1, root, pn, ps=20, sort` (1 hot / 0 time) | – | `thread(aid:root:page:sort:)` | `CommentThreadData` → `ThreadPage` (root, replies, page.count/num/size) |
| `/x/v2/reply/add` | POST | `oid, type=1, message`, `root?`, `parent?`, `sync_to_dynamic=1?` (Referer `…/video/av{aid}`) | C | `postComment(...)` | `PostedComment.reply` → `Comment` |
| `/x/v2/reply/action` | POST | `oid, type=1, rpid, action=1/0` | C | `likeComment` | none |
| `/x/v2/reply/hate` | POST | same | C | `hateComment` | none |
| `/x/v2/reply/del` | POST | `oid, type=1, rpid` | C | `deleteComment` | none |
| `/x/emote/user/panel/web` | GET | `business=reply` | – | `emotePackages()` | `EmotePanel.packages[]` → `EmotePackage` (id, text, url, type 4 = text, `emote[]{text,url,meta.size}`) |
| `/x/v2/dm/web/seg.so` | GET (protobuf) | `type=1, oid=cid, segment_index` (1-based) | – | `danmakuSegment(cid:index:)` (+Danmaku), via `getData` | `DanmakuSegment.decode` |
| `/x/v2/dm/wbi/web/seg.so` | GET | same | W | fallback on HTTP 403 or 412 | same |
| `/x/dm/filter/user` | GET | – | – | `danmakuBlockRules()` | `rule[]{id,type,filter}` → `BlockRule` |
| `/x/dm/filter/user/add` | POST | `type` (0 keyword / 1 regex / 2 user), `filter` | C | `addBlockRule` | `BlockRuleItem` |
| `/x/dm/filter/user/del` | POST | `ids` | C | `deleteBlockRule(id:)` | none |
| `/x/v2/dm/post` (send danmaku) | POST | `type=1, oid=cid, bvid, msg, mode, fontsize, color` (decimal), `progress` (ms), `rnd` (unix µs), `pool=0`, `colorful=60001` when gradient (Referer = video page) | C | `postDanmaku(DanmakuDraft)` | `dmid` (0 if absent) |
| passport `/x/passport-tv-login/qrcode/auth_code` (TV login) | POST, cookie-less | `local_id=0` + appkey/ts/sign | A | `tvAuthCode(signer:)` (+App) | `{url, auth_code}`; the user confirms the URL in a signed-in web view |
| passport `/x/passport-tv-login/qrcode/poll` | POST, cookie-less | `auth_code, local_id=0` + appkey/ts/sign | A | `tvPoll(signer:authCode:)` | code 0 → `.confirmed(access_token, mid)`; 86039/86090 → `.waiting`; 86038 → `.expired`; other codes throw |
| app `/x/v2/view/dislike` (不喜欢) | POST, cookie-less | `aid`, `dislike` (**`"0"` when dislike on, `"1"` to take it back**), `access_key` + appkey/ts/sign | A | `dislike(aid:on:accessToken:signer:)` | none |

**Not in the package:**
- Web login: `D:\Repos\Apps\BiliNative\ios\Sources\App\Account\LoginView.swift` loads `https://passport.bilibili.com/login` in a WKWebView and copies the bilibili.com cookies once `SESSDATA` appears. There is no QR-web-login API call.
- No separate 合集/season endpoint (it comes from `ugc_season` in `wbi/view`), no search, no buvid activation call beyond spi.

**Related public types** (`TrackSelector.swift`):
- `VideoCodec` codecids: hevc 12, av1 13, avc 7.
- `TrackSelector.choose` takes the highest qn ≤ the request (else the lowest offered), then the first codec in the order given.
- Audio is AAC only, ranked 30280 > 30232 > 30216.
- `codecKind` reports "dolby" for dvh1/dvhe or id 126.

---

## 4. The BTR engine (`D:\Repos\Apps\BiliNative\ios\Packages\BiliCore\Sources\Ripper\`)

### Transport
- `Transport.swift` defines `protocol RangeTransport`:
  - `fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse{status, headers (lowercased), body: AsyncThrowingStream<[UInt8]>}`.
  - `connectionsPerHost: Int?` (default nil).
  - It returns once headers arrive. Cancelling the task or dropping the body must cancel the request.
- `RipperError`: firstByteTimeout, stalled, attemptTimeout, badResponse(status), lengthMismatch, totalMismatch, noNodes, invalidURL, closed.
- `URLSessionRangeTransport.swift`:
  - Ephemeral session, `httpMaximumConnectionsPerHost = 8` by default, no cache, no cookies, a serial delegate queue.
  - Uses delegate streaming, which works with swift-corelibs on Windows.
  - Its `abandon` ends a call at once, so a cancelled hedge copy gives its permit back immediately.
  - The app builds it with `BiliClient.mediaHeaders` (UA and Referer).

### `RipperConfig` fields and defaults (`RipperConfig.swift`)
| Field | Default | Meaning |
|---|---|---|
| `firstByteTimeoutMs` | 5,500 | |
| `stallTimeoutMs` | 4,000 | |
| `attemptTimeoutMs` | 15,000 | |
| `hedgeDelayMs` | 900 | |
| `minChunkBytes` | 64 KiB | |
| `pieceRounds` | 3 | |
| `retryWindowMs` | 25,000 | |
| `fixedConcurrency` | nil | nil lets AutoConcurrency decide |
| `prefetchVideoBytes` | 64 MiB | |
| `prefetchAudioBytes` | 8 MiB | |
| `prefetchAheadSeconds` | 45 | |
| `priority` | 50 | player requests; prefetch uses 10 |
| `hurry` | true | kill switch for hurry mode |
| `hurryAheadSeconds` | 10 | |

### Features and where they live

**Node catalog** (`NodeCatalog.swift`)
- Mainland nodes: upos-sz-mirrorali, hw, bos, 08c, bd, 14b, estgoss, cos.
- Overseas nodes: upos-sz-mirrorcosov, upos-sz-mirroraliov, cn-hk-eq-01-01, cn-hk-eq-01-03 (all `.bilivideo.com`).
- `NodeMode`: `.mainland`, `.overseas`, `.custom([NodeAddress])`. An empty custom list acts as mainland.
- `MediaURLPolicy.bilibili` accepts only:
  - https,
  - no userinfo,
  - a plain host name (regex),
  - a path ending in .m4s/.mp4/.flv,
  - a host under bilivideo.com/.cn/.net, akamaized.net, szbdyd.com, hdslb.com, xycdn.com, mountaintoys.cn, nexusedgeio.com or ahdohpiechei.com.
- `representationURLs`: the allowed originals for the mode, then the signed address swapped onto every node.
  - The swap donor is the first non-Akamai original.
  - When only Akamai originals exist, every original is swapped onto every node (`allowAkamai`).
  - `swapHost` also resets the port.
- Keys: `nodeKey` = host[:port]; `address` = path+query; `isAkamai` = `.akamaized.net`.

**Resolver** (`Resolver.swift`, one per track)
- `urls()` leaves banned addresses out, unless that would leave none.
- `ordered(pieceIndex:)` rotates.
- `rangeCandidates()`:
  - Warm-up: the first 4 ranges (1 in mainland) go to every node.
  - Afterwards up to 6 nodes: measured ones fastest first, plus at least one unmeasured or stale node as exploration, and at least 3 nodes.
- `startupCandidates()`: Bilibili's originals plus all URLs, at most 8. Custom mode skips the originals.
- `rescueCandidates()`.
- `success`: route speed EWMA 0.65 old / 0.35 new, keyed by node+path so a new signature keeps the speed. Measurements expire after 90 s (`measurementTTL`).
- `sample()`: a cut-off transfer's speed counts without proving the address.
- Failure backoff: `blockedUntil = now + min(60 s, 3 s × 2^min(failures,4))`.
- `status()` gives healthy/untested/blocked/banned per address; `NodeStatus.best` picks the best per node.

**Ban list and ban healing** (`BanList.swift`, default limit 2)
- Only replies with 0 bytes received count as strikes.
- Blame:
  - Silent failure → node.
  - 4xx by a node that has delivered → address (or pair, if the address has also delivered).
  - 4xx of an address that has delivered, by a node that has not → pair only.
  - 4xx before anything has delivered → nobody.
- Losses within 250 ms (`lossMomentMs`) of the first loss of a moment are one strike, and the window does not stretch.
- `success()` clears a node's silent strikes and lifts a node ban they caused. That is the healing.
- `reset()` runs on a network change.

**Damaged spans** (`Resolver.failure` / `avoids`)
- When a node that is up breaks off without a status and not by timeout, the damage is recorded per route from that byte to the end of its 1 MiB block (`damageBlock = 1<<20`).
- At most 2 blocks per node and file (`damagedBlockLimit`); damage in a third block is struck as normal.
- No strike and no backoff. `PieceDownloader` keeps pieces off nodes whose damaged span they touch.
- `resetHealth` forgets the damage.

**Full-node rule**
- `NodeStats.isFull`: inflight ≥ limit, with limit = transport `connectionsPerHost` (8) for Akamai from the start.
- `PrimaryAssigner` lets a full node sit out its turns.
- `CopyTargets` (`PieceDownloader.swift`) claims a node only once the copy holds a permit, through `NodeStats.begin(firstOpenOf:)`.

**Busy-node rule** (`Attempt.swift`)
- A first-byte timeout with 0 bytes, on a node that is receiving other pieces, is not a strike and not a `slow()` signal. It is logged with `busy: true`.
- `NodeStats.silent` caps the node's limit at what it was receiving.

**Hurry mode**
- In a hurry when it is a startup or seek read, or the segment starts less than `hurryAheadSeconds × rate` ahead of the playhead. Re-read on every check (`RipperSession.hurry(for:)`).
- `RangeDownloader.swift`:
  - Uses the 64 KiB `minChunkBytes` instead of the adaptive size.
  - Skips the probe head when a node is already known.
  - Places pieces with `HurryPlacement.assign`.
- `HurryPlacement.swift`:
  - Cost is expected finish time. An unknown node costs best × 2 × (inflight+1).
  - +1e5 when crowded (more than 2 hosts, inflight ≥ 2, more than half of all inflight).
  - +1 when the node has not delivered; +1e6 when it is full.
  - `byExpectedFinish` orders later copies the same way, without the crowded term.
- `PieceDownloader.hurryHedgeDue`:
  - With no first byte yet: `clamp(ttfb×2, 250, 600)` ms, or 250 ms when ttfb is unknown.
  - 1 s with no progress.
  - `elapsed ≥ max(400, expected×2)` while under 75% has arrived. An unmeasured node uses the best candidate's expected time, else `hedgeDelayMs`.
  - Up to 3 copies; outside a hurry there is never a third.

**Node stats** (`NodeStats.swift`, shared by both tracks)
- Tracks inflight, receiving, ttfb, bps and load per node.
- EWMA 0.7 old / 0.3 new (`smoothed` in `Meter.swift`).
- Bodies under 32 KiB are ignored.
- `outrun` raises ttfb. `crawl` lowers bps only after ≥ 300 ms and only when slower than the current speed.
- `expectedMs = ttfb + bytes / (bps × max(4,load) / max(width, inflight+extra+1))`.
- `reset()` clears measurements but keeps the running counts.

**Hedged copies** (`PieceDownloader.swift`)
- Up to `pieceRounds` rounds, each walking the candidates 3 at a time (a probe uses all of up to 8).
- Copy 2 starts at `Meter.hedgeDelayMs` = `max(250, min(900, typicalPieceMs×1.5))`. Startup uses `min(200 with deadline / 250, measured)`. With a finite deadline it follows BTR `hedgeDue`.
- Hedge copies get +20 priority.
- Bytes already received are kept as a resume prefix (min 32 KiB, `resumeMinBytes`).
- Round pause: `min(2 s, 0.5 s × 2^(round-1))` while inside `retryWindowMs`.
- Losing copies are cancelled. Their bytes are sampled (`resolver.sample`, `streamed`) and never struck.

**Attempt** (`Attempt.swift`)
- Waits for a pool permit, then the claim picks the node.
- Watchdog every 25 ms enforces the three timeouts.
- Requires a 206 whose `Content-Range` equals the requested part, and an exact length.
- On success it feeds Meter, NodeStats, `resolver.success` and EngineStats.
- On 412/429 it calls `auto.pushback`; on a timeout with 0 bytes it calls `auto.slow()`.

**Range download** (`RangeDownloader.swift`)
- `meta()` races init+index over up to 3 startup candidates started 0/120/300 ms apart, priority 220, class `.critical`.
- `stream()` yields pieces in file order and checks that every piece's advertised total agrees (`totalMismatch`).
- Startup outside a hurry: a probe head of `max(64 KiB, minChunk)` raced over every candidate.
- Rescue reserve: `min(8, max(1, ⌈limit/8⌉))` connections when limit ≥ 8.
- Piece priority: startup 120 − min(30,i); otherwise priority − min(20,i).

**Primary assignment outside a hurry** (`PrimaryAssigner.swift`)
- Smooth weighted turns with weight `max(speed, top×0.05)`.
- Nodes under top/12 get nothing.
- Unknown nodes get `min(unknown×2, count/4)` trial pieces from the end. Small ranges give one trial every 4th range.

**Meter** (`Meter.swift`)
- Samples ≥ 48 KiB only.
- `adaptiveMinChunk = max(base, min(1 MiB, ⌊bps×0.6/64Ki⌋×64Ki, ⌈range / max(1, min(max(4,hosts), pieceLimit))⌉))`.

**Connection pool** (`ConnectionPool.swift`, BTR Semaphore)
- Limit clamped to 1..512.
- Order: class first (critical < startup < ordinary), then rank = priority + urgency + aging.
  - Urgency: overdue +12, ≤ 750 ms +9, ≤ 2 s +6.
  - Aging: `20/900` per ms, only for ordinary requests with a finite deadline.
- `onChange` is called outside the lock.

**Automatic connection count** (`AutoConcurrency.swift`)
- Ladder `[8,12,16,24,32,48,64]`. Each new session starts at index 2 (16) and steps back down once 15 s is buffered, or after 30 s.
- Step-up cooldown 2.5 s. A step up is a 10 s trial: if throughput has not grown, it is taken back and that level rests 90 s.
- 412/429 steps down and hard-blocks the level for 180 s.
- Low-buffer pressure: below 6 s ahead and not growing for 1 s while downloading.
- Throughput window 5 s with 250 ms buckets. `slow()` steps up only at saturation ≥ 0.6.
- Reason strings are Chinese (起步, 播放卡了一下, 缓冲跟不上播放, 连接排队等太久, …).

**Prefetch and kept prefetches** (`RipperSession.swift`)
- After each read, `schedulePrefetch` fetches the following segments within 45 s of the playhead and under the per-track byte cap, at priority 10. It skips segments already cached, in flight or pending for the player.
- A player read adopts an in-flight prefetch by taking it out of `inflight`. If the reader is cancelled, `returnPrefetch` hands it back, unless the session closed, a seek happened (`seekGeneration`) or the segment was scheduled again.
- On a seek, `dropPrefetch(track)` cancels that track's prefetches and calls `auto.newSession()`.
  - Seek rule: segment position < last−1 or > last+2.
  - Unaligned ranges: start < prev.start − len, or start > prev.end + 1 + len.
- `updatePlayhead` evicts cache entries ending more than 2 s behind the playhead.
- `dropCache()` runs on memory warnings. `onFatal` is reported once per batch of failing requests.

**Network change** (`RipperSession.networkChanged(interfaceChanged:)`)
- Calls `bans.reset()`, `resolver.resetHealth(clearMeasurements: interfaceChanged)` and `nodes.reset()`.
- The app (`PlaybackController.swift`, `NWPathMonitor`) calls it only when the path signature (up, interface names, gateways) changes.

**Stats**: `EngineStats.swift` → `RipperStats` (delivered and duplicate bytes, requests, failures, cache hits, concurrency, per-node timings, node states).

---

## 5. HLS bridge for AVPlayer

**Package side**
- `SidxParser.parse(bytes, absoluteStart:)` (`DashHLS\SidxParser.swift`)
  - Reads the first `sidx` box, v0 or v1, including timescale and first_offset.
  - Segment *k* gets byte start `absoluteStart + box.end + first_offset + Σ sizes` and time `earliest/timescale + Σ durations`.
  - Any type-1 (hierarchical) reference rejects the whole index. Overflow is guarded.
- `InitSegmentFixer.fixHEV1` (`DashHLS\InitSegmentFixer.swift`)
  - Walks moov→trak→mdia→minf→stbl→stsd; entries start at stsd payload+8.
  - For each `hev1` entry, finds `hvcC` after the 78 fixed VisualSampleEntry bytes and reads its arrays from payload+22.
  - If NAL types 32/33/34 (VPS/SPS/PPS) all have count > 0, it rewrites bytes `entry.start+4..+8` to `"hvc1"`.
  - Otherwise `.unplayable`. Also `.unplayable` for a truncated hev1 entry, or an `ftyp` with no complete `moov`.
  - `sampleEntry()` reports the first entry type.
- `CodecMapper.video` (`DashHLS\CodecMapper.swift`)
  - `dvh1.08.07`/`08.03` → `hvc1.2.4.L153.b0`, SUPPLEMENTAL `…/db4h`, HLG.
  - `dvh1.08.06` → `hvc1.2.4.L150` + `/db1p`, PQ.
  - `dvh1.05*` → unchanged, PQ.
  - A `hev1…` label becomes `hvc1…` when the served sample entry is hvc1.
  - qn 125 → PQ; everything else SDR.
  - `frameRate` is formatted `%.3f`, default `30.000`.
- `PlaylistBuilder` (`DashHLS\PlaylistBuilder.swift`)
  - Media playlist: `#EXT-X-VERSION:7`, `TARGETDURATION=ceil(max dur)`, `MEDIA-SEQUENCE:0`, `PLAYLIST-TYPE:VOD`, `INDEPENDENT-SEGMENTS`, `EXT-X-MAP:URI="<uri>",BYTERANGE="len@start"`, then per segment `#EXTINF:%.3f,` + `#EXT-X-BYTERANGE:len@start` + the uri, then `#EXT-X-ENDLIST`.
  - Master playlist: `EXT-X-MEDIA TYPE=AUDIO,GROUP-ID="audio",NAME="default",DEFAULT=YES,AUTOSELECT=YES,URI=…` and `EXT-X-STREAM-INF` with BANDWIDTH = avg×1.5, AVERAGE-BANDWIDTH = video+audio bandwidth, CODECS, SUPPLEMENTAL-CODECS (optional), RESOLUTION, FRAME-RATE, VIDEO-RANGE, `AUDIO="audio"`.
  - Lines are joined with `\n`.
- `PlaybackRouter` (`LocalHTTP\PlaybackRouter.swift`)
  - `register(PlaybackAssets{playlists:[name:String], media:[name:MediaResource]}) → token`. The token is 128 random bits as 32 hex chars.
  - Path must be exactly `/<token>/<name>`, method GET or HEAD only (405 otherwise; 404 for unknown paths).
  - Playlists are served as `application/vnd.apple.mpegurl`.
  - Media is served as `video/mp4` with `Accept-Ranges: bytes`, Content-Length, and Content-Range on 206; 416 carries `bytes */total`.
  - `MediaResource.prefix` (patched init+index) is served from memory and spliced with `read(range)` for the rest.
  - `lengthChecked` fails a body that is shorter or longer than advertised.
- `RangeRequest.parse`: single ranges `a-b`, `a-` and `-n`; the end is clamped; a multi-range request is unsatisfiable.
- `HTTPRequestParser`: 16 KiB header cap; lowercased header names; path without the query.

**App side** (not in the package)
- `D:\Repos\Apps\BiliNative\ios\Sources\App\Playback\LocalServer.swift`
  - NWListener bound to `127.0.0.1` on port `.any`, so the OS picks an ephemeral port. URLs are `http://127.0.0.1:<port>/<token>/<name>`.
  - One request per connection, `Connection: close`.
  - A client close cancels the responder task, which drops the stream and cancels the engine read.
  - `answers()` probes over loopback, because iOS can take a suspended app's socket silently.
- `D:\Repos\Apps\BiliNative\ios\Sources\App\Playback\PlaybackBuilder.swift`
  - File names: `master.m3u8`, `v.m3u8`, `a.m3u8`, `v.mp4`, `a.mp4`.
  - `ripperAssets` maps `v.mp4`/`a.mp4` to `MediaResource(totalSize, prefix: patched headers) { range in session.read(.video/.audio, range) }`.
  - The playlist `EXT-X-BYTERANGE`s are the SIDX segment ranges, so each AVPlayer segment request is one `RipperSession.read(track, range)`, which the engine splits into pieces.
  - It requires a complete `moov` inside the init range. Only the video init is patched.
- Direct mode: `DirectPlaylistLoader.swift` uses the custom scheme `bilinative://playlist/<token>/<name>` through `AVAssetResourceLoaderDelegate`. Media URIs point straight at the CDN, with the `AVURLAssetHTTPHeaderFieldsKey` headers.
- `PlaybackController.swift`: signed URLs are refreshed 300 s before their `deadline` (`urlMarginSeconds`) through `session.replaceURLs`.

---

## 6. DevLog

**Event schema** (`DevLog\LogEvent.swift`)

`{t: Double unix seconds, seq: Int64, session: String (16 hex chars), level: debug|info|warn|error, cat: app|api|engine|server|player|ui, msg: String, f: {String: string|int|double|bool}}`
- Non-finite doubles are encoded as `"nan"`, `"inf"`, `"-inf"`.
- `Logger.log` runs `Redactor.text` on msg and `Redactor.fields` on f.
- `Logger.add(sink)` returns the last seq handed out before the sink joined.

**Event messages the package emits**
- `api`: the request path (fields status, code, ms), `"<path> decode failed"`, `"resolve short link"`.
- `engine`: `piece`, `attempt cancelled`, `attempt failed` (with `busy`), `ban` (node, strikes, kind), `threads`, `headers`, `urls replaced`, `network changed, node health reset`, `range failed`, `read` (source memory/prefetch/fetch, seek), `prefetch failed`.
- The app adds `server` (GET/HEAD per local request), `player`, and `app` events; crash and hang arrive as `app` events in DEV_TOOLS builds.

**Redactor** (`DevLog\Redactor.swift`)
- Field keys containing sessdata, bili_jct, jct, csrf, cookie, authorization, access_key, token, password/passwd/pwd or dedeuserid__ckmd5, or exactly `sign`, become `[redacted]`.
- `mid` and `dedeuserid` are hashed (FNV-1a → `mid:xxxxxxxx`).
- URLs are cut to scheme://host[:port]/path, keeping only `?deadline=`.
- Cookie and Set-Cookie headers keep the names and drop the values. Authorization, Bearer and name/value secret pairs in free text are blanked.

**Sinks**
- `FileSink`: `<dir>/<session>.jsonl`, 20 MB cap. The live file is sealed as `<session>.<n>.jsonl` at a quarter of the cap; the oldest files are pruned. `exportFile()` writes `../BiliNative-logs.jsonl`. The app's directory is `Caches/logs`.
- `NetworkSink`:
  - Posts every 500 ms, buffers at most 10,000 events (oldest dropped), at most 2,000 per batch.
  - Backoff doubles up to 30 s and resets on success.
  - Body is NDJSON (one JSON object per `\n`).
  - Events are removed after a successful post; `onAcknowledged(session, seq)` reports the watermark.
- `AckStore` writes `ack.json`. `ReplayPlanner.unsent` resends unconfirmed events from session files, newest first, and `prepend`s them ahead of live events.

**PC protocol** (`D:\Repos\Apps\BiliNative\tools\logserver.py`, run with `uv run`)
- `ThreadingHTTPServer` on `0.0.0.0:47321` (`--port`).
- `POST /logs`: body split on `"\n"`, each line JSON (an unparsable line becomes a warn event). Reply `200 ok`, `Connection: close`.
- `GET /health` → `ok`.
- Writes `logs/<YYYY-MM-DD>/<session>.jsonl`; the session name keeps alphanumerics only, max 64 chars.
- Bonjour (`zeroconf`): type `_bilinative-log._tcp.local.`, name `BiliNative log on <hostname>`, property `path=/logs`. `--no-bonjour` and `--quiet` turn these off.

**App side**
- `D:\Repos\Apps\BiliNative\ios\Sources\App\DevTools\LogPoster.swift` sends one NWConnection per batch: `POST /logs HTTP/1.1`, `Host: bilinative-log`, `Content-Type: application/x-ndjson`, `Connection: close`. Connect timeout 3 s, whole exchange 10 s, success requires `" 200 "` in the status line.
- The target is a Bonjour service name (`LogServerDiscovery.swift`, NWBrowser) or a manual `IP:port` (default port 47321).
- `DevLogSetup.swift` wires it up and replays the backlog.

**DEV_TOOLS gating**
- The package's sinks are not gated.
- The app gates `LogPoster`, `LogServerDiscovery`, `CrashReporter`, `CrashReport`, the network part of `DevLogSetup.apply` and the 开发者 settings with `#if DEV_TOOLS`.
- `ios\project.yml` currently sets `DEV_TOOLS` in **both Debug and Release** for the app and its unit tests. The comment says a public release build would drop it. CI checks that Debug has `DEBUG DEV_TOOLS` and Release has `DEV_TOOLS`.
- `FileSink` is always installed.

---

## 7. Tests (`D:\Repos\Apps\BiliNative\ios\Packages\BiliCore\Tests\`)

8,247 lines and 546 tests in total. Format per file: lines / tests.

**AppLogicTests** (385 lines, 47 tests)
- Autoplay 61/10, CountFormat 21/2, GestureMath 45/7, HeartbeatSchedule 57/7, HistoryGrouping 55/4, QualityNames 36/5, QualityRules 26/4, ResumePoint 22/3, TimeFormat 62/5.
- Each covers the matching rule in section 9.

**BiliAPITests** (2,403 lines, 179 tests)
- ActionsAPITests 297/27: relation, card, like, triple, coin, coin balance, favourite folders, batch-deal, folder add, share, follow, tags, no-csrf refusal.
- AppSignerTests 166/10: signer against a documented vector, TV auth_code and poll states, dislike without cookies or csrf, no 412 retry when cookie-less.
- BiliClientTests 216/12: nav and WBI cache, playurl flags and signature, spi, notDash, the 412 retry, short links, redirect cookie stripping, CookieJar.
- BiliHostsTests 16/2.
- CommentsAPITests 367/15: decoding, pinned comment, cursor, the unsigned fallback, threads, add/like/hate/del, emotes.
- DanmakuAPITests 281/19: seg.so and the WBI fallback, block rules, post form.
- FeedAPITests 171/9: rcmd query and filter, history cursor rules, `dt` device kinds.
- Fixtures 84/0.
- LinkParserTests 41/5.
- ModelsTests 176/20: camelCase and snake_case spellings, lossy arrays, durl.
- PostTests 212/19: csrf, headers, form encoding, getData, hosts.
- RichTextTests 94/13.
- TrackSelectorTests 63/8.
- VideoAPITests 185/15.
- WBITests 34/5: MD5 vectors, mixin key, the w_rid reference vector.

**BiliSharedTests** (61 lines, 6 tests): ByteRange 41/4 (including split matching BTR), Locked 20/2.

**DanmakuTests** (486 lines, 41 tests)
- FilterTests 116/12, LaneLayoutTests 94/8, ProtobufReaderTests 76/5, ProtobufWriter 48/0 (a test-only encoder), SegmentTests 94/9, TimelineTests 58/7.

**DashHLSTests** (463 lines, 36 tests)
- InitSegmentFixerTests 183/18, MP4Builder 40/0 (a builder for synthetic sidx, hvcC and init segments), PlaylistBuilderTests 91/6, RealHEV1InitSegment 53/0 (base64 of a real ffmpeg `-tag:v hev1` 128×72 x265 ftyp+moov, 3,195 bytes), SidxParserTests 96/12.

**DevLogTests** (470 lines, 39 tests): FileSink 164/9 (roll, prune, replay, ack), Logger 48/4, NetworkSink 99/6, Redactor 159/20.

**LocalHTTPTests** (314 lines, 13 tests): parser, Range variants, router prefix splicing, HEAD, length checks, tokens.

**RipperTests** (3,665 lines, 185 tests)
- AttemptTests 271/18, AutoConcurrencyTests 88/7, BanListTests 155/12, ConnectionPoolTests 320/17, HurryPlacementTests 108/6, LoopbackServer 210/0, NetworkChangeTests 71/4, NodeCatalogTests 120/16, NodeStatsTests 230/13, PrimaryAssignerTests 70/7, RangeDownloaderTests 907/42 (end-to-end over SimCDN: hedging, bans, damage, hurry, busy and full nodes, blips), ResolverTests 179/16, RipperSessionTests 557/22 (cache, prefetch, seek, adoption, fatal reporting), SimCDN 273/0, URLSessionRangeTransportTests 106/5.

**Test helpers**
- `SimCDN` (`RipperTests\SimCDN.swift`) is an in-memory `RangeTransport` serving one byte pattern (`i*31+7`) on every node. Per node (host[:port]) a `Behavior` sets:
  - `firstByteMs`, `bytesPerSecond`, `status`, `failForMs` (connection errors for the first N ms),
  - `truncateAfter`, `stallAfter`, `wrongRange`, `omitContentRange`, `extraBytes`, `totalSize` (an advertised total that lies),
  - `coldRequests`/`coldFirstByteMs`, `lateFirstByteFromRequest`, `refusedQueries` (403 for `os=…`),
  - `missing` (Akamai's damaged span: no response when the request starts inside it, cut off when it runs into it),
  - `coldRange` with its own first-byte delay and speed.
  - With `connectionsPerHost` set, `HostConnections` gives Akamai nodes an 8-per-host HTTP/1.1 queue and records `peakWaiting`.
  - `TestEngine` holds the test config (first byte and stall 300 ms, attempt 3 s, hedge 100 ms, retry window 5 s, fixed 8 connections), node names and helpers.
- Other transports: `ScriptedTransport` (RipperSessionTests: gating, refuse/hold/lie from an offset, range recording), `RecordingTransport` (RangeDownloaderTests), `FakeHTTP` (BiliClientTests: routes by path or `"METHOD path"`, data routes, redirects, request capture, fixed clock `1_702_204_169`).
- `LoopbackServer`: a blocking 127.0.0.1 socket server (WinSDK or Darwin) with `hang`, `trickle` and `complete(n)` behaviours, for testing the real URLSession transport.

**JSON fixtures**: there are no `.json` files and no test resources. Fixtures are Swift raw strings in `BiliAPITests\Fixtures.swift`:
- `navLoggedOut`, `navLoggedIn` (with WBI img/sub URLs)
- `view`, `viewDetail` (2 pages, `ugc_season` with 2 sections and 3 episodes, desc_v2 mention, honor)
- `playerV2` (3 type-2 chapters), `playerV2Highlights` (type 1)
- `related` (one redirect_url ad), `online`, `playURLResume`
- `spi`, `notFound` (-404)
- `playURL`: qn 120 HEVC hev1 with camel and snake spellings, AVC, AV1 at 80, Dolby `dvh1.08.07` at 126, audio 30216 and 30280
- `durlOnly`

Other test files also carry inline JSON.

---

## 8. Danmaku

- **Format**: protobuf. `seg.so` returns DmSegMobileReply: field 1 = repeated elem (length-delimited), field 2 = state varint, where 1 means closed (`DanmakuSegment.decode`).
- **`DanmakuElem` fields**: 1 id, 2 progress (ms), 3 mode, 4 fontsize, 5 color, 6 midHash (string), 7 content, 8 ctime, 9 weight, 11 pool, 12 idStr, 13 attr, 24 colorful. A known field in the wrong wire type is skipped.
- **`ProtobufReader`**: varint (10-byte cap), length-delimited, skip for wire types 0/1/2/5.
- **No XML anywhere.**
- **Segments**: 6 minutes (`lengthMs = 360_000`), index = `ms/360000 + 1`. `needed(atMs:loaded:durationMs:)` adds the next segment within 30 s of the boundary.
- **Filtering** (`DanmakuFilter.apply`)
  - Modes 7–9 are always dropped.
  - Type blocks: scroll = modes 1 and 6; bottom = mode 4 (also `hideBottom`); top = mode 5. `blockColored` drops color ≠ 0xFFFFFF or colorful ≠ 0.
  - Rules (when `applyRules`): keyword is a substring match; regex is case-insensitive with `/…/` stripped, and an empty pattern is skipped; user matches `midHash`.
  - Danmaku whose midHash equals the user's own hash are exempt from rules and never merged.
  - Output is stable-sorted by progress.
  - `dedupe`: same content within 10 s merges into `"text ×N"`. `blockCount` drops merged groups.
  - `DanmakuFilterOptions` is Codable; missing keys take the defaults.
- **Block words** come from the server (`/x/dm/filter/user*`); `BlockRule.Kind` 0 keyword, 1 regex, 2 user. `MidHash.of(uid:)` = CRC-32 (0xEDB88320) of the decimal uid, lowercase hex with no leading zeros.
- **Timeline** (`DanmakuTimeline`): advances on the player clock. A step backwards or of more than 1 s is a seek and emits nothing. Ties keep arrival order.
- **Lane layout** (`LaneLayout`, in the package)
  - Scroll speed is `(screenW + w)/scrollDuration`.
  - A lane is free when the danmaku ahead has fully entered and the new one cannot catch it before it leaves.
  - Top and bottom lanes are busy for `staticDuration` (default 4 s). Bottom lanes count from the bottom.
  - Returns nil, meaning drop, when no lane is free.
- **Sending**: `postDanmaku` (section 3). `DanmakuDraft{cid,bvid,text,mode,fontSize,color,gradient,progressMs}`.

---

## 9. AppLogic (`D:\Repos\Apps\BiliNative\ios\Packages\BiliCore\Sources\AppLogic\`)

- **QualityRules.swift**: `needsVip(qn) = qn >= 112`. `auto(offered:isVip:)` returns the highest allowed qn.
- **QualityNames.swift**: the official app's full names (127 8K 超高清 … 16 360P 流畅) and short button names (8K, 杜比视界, HDR, 4K, 1080P60, 1080P+, 1080P, 720P60, 720P, 480P, 360P, 240P), falling back to the server text.
- **ResumePoint.swift**: resume only for the same cid, when > 0 and more than 5 s remain.
- **Autoplay.swift**: `next(after:parts:episodes:autoplay:loop)` with `LoopMode` single/list/none.
  - Order: next part, then next 合集 episode (found by cid, then bvid).
  - A list loop wraps to the first episode (or first part).
  - Single loop replays.
- **GestureMath.swift**: 90 s of seek per screen width, axis lock after 10 pt (a tie counts as horizontal), edge inset 25. Level change is −dy/height, clamped to 0…1.
- **HeartbeatSchedule.swift**: `tick` reports every 15 s of position while playing. `mark` always reports. `finished = -1`. NaN or negative positions report 0.
- **HistoryGrouping.swift**: one section per calendar day in a given time zone: 今天 / 昨天 / `M月D日` / `YYYY年M月D日`.
- **TimeFormat.swift**:
  - `clock`: m:ss or h:mm:ss.
  - `pair`.
  - `publish`: `YYYY年M月D日 HH:mm`.
  - `relative`: 刚刚 / N分钟前 / N小时前 (elapsed time), then by calendar 昨天 HH:mm, MM-DD, YYYY-MM-DD.
- **CountFormat.swift**: below 10,000 the number as is; then 万 / 亿 with one decimal, truncated.
- Related pure logic outside AppLogic: `TrackSelector` (codec and audio choice), `RichText` (emote > mention > link (match_once) > BV/av > timestamp runs), `LinkParser`, `DanmakuSegments.needed`.

---

## 10. Windows-specific notes for `swift test --package-path ios/Packages/BiliCore`

- `CLAUDE.md` states the package must build and pass `swift test` on Windows and macOS. It is Foundation-only, Swift 5 mode.
- `FoundationNetworking` is imported under `#if canImport(FoundationNetworking)` in `HTTP.swift`, `URLSessionRangeTransport.swift` and 5 BiliAPI test files.
- `URLSessionRangeTransport` deliberately uses delegate callbacks so it works with swift-corelibs-foundation on Windows.
- MD5 and CRC-32 are hand-written; no CryptoKit or zlib is imported.
- `LoopbackServer.swift` uses WinSDK sockets on Windows (`WSAStartup`, `SOCKET`, `WinSDK.send`), bound to 127.0.0.1 so Windows Firewall never prompts.
- A timing note in `RangeDownloaderTests.swift` (line 201): one round's walk over the nodes takes about 0.4 s on Windows, so the blip test uses a 1.4 s failure window. `TestEngine.slowConfig` raises the stall timeout for loaded runners.
- `DanmakuFilter` comment: NSRegularExpression accepts `""` on Apple platforms, so empty patterns are skipped explicitly.
- `CLAUDE.md` adds three environment facts:
  - Swift 6.4.1 is installed at `D:\Tools\Swift`.
  - A `wchar_t ... broken by a context change` warning from WinSDK appears a few times per run and can be ignored.
  - Sideloadly's `an\` folder must not be on PATH.
- CI (`.github\workflows\ios-compile.yml`) runs `swift test` only on pushes to `main`. Other branches rely on the PC run.

---

## `docs/background.md`: rules a Dart port must keep

**Prior art and what it is good for**
- PiliPlus and ATV-Bilibili-demo: endpoints and formats only (GPL); do not copy their code.
- BTR is MIT; keep the notice. The port follows tag `2026.10.8.1` (`range-core.js`, `cdn-resolver.js`, `idm-downloader.js`, `sidx.js`).
- The lemonteaau notes for a localhost Range proxy:
  - A player disconnect must cancel downloads at once.
  - A new request on the same track supersedes the old one.
  - mpv buffers only about 16 s.
- btr-ios on a real iPhone:
  - The official player asks about 1 MB at a time (`Range a-b`, one at a time) and also opens `bytes=a-`. There is no certificate pinning.
  - Splitting each 1 MB request over several nodes was slower, because new connections never leave TCP slow start. Gains need fetching ahead over warm connections.
  - AVPlayer asks for whole SIDX segments (a few seconds each), which suits BTR.

**What Bilibili's CDN nodes actually do** (measured 2026-09-19, overseas, 1080P+ HEVC)
- Hot vs cold content:
  - Akamai (`upos-hz-mirrorakam.akamaized.net`): hot first byte 20–200 ms, 5–9 MB/s per connection (the fastest); cold first byte 0.9–1.6 s.
  - aliov: hot 25–50 ms, about 4 MB/s; cold ~40 ms first byte, then 45–100 KB/s.
  - cosov: hot 180–370 ms, about 3 MB/s; cold ~200 ms and ~0.7 s per 70 KiB, the most dependable cold.
  - cn-hk-eq-01-01/03: 600–1200 ms first byte, 20–200 KB/s.
- Protocols: cosov, aliov, the HK nodes and the mainland mirrors use HTTP/2 (one TCP connection per host, so parallelism = distinct nodes). Akamai is HTTP/1.1 only.
- Piece size: 64 KiB pieces never leave slow start (aliov 394 KB/s at 64 KiB vs 4,158 KB/s at ~400 KiB). Large pieces lose on cold content (one 400 KiB piece took 3.9 s).
- Akamai-only accounts: the primary `os=cosovbv` address got 403 everywhere while the `os=akam` backup worked on every node, so Akamai addresses become host-swap donors and bans are scoped to node, address or pair. On 2026-10-16 only Akamai refused `os=cosovbv`.
- Damaged edge copy (2026-10-16): Akamai's q80 HEVC copy lacked bytes 109972–1048575.
  - A range crossing 109972 got a 206 and was cut off there.
  - A range starting inside the gap got no response at all.
  - Everything from 1 MiB on was whole. The mirrors served the whole file.
- Seek cost: 1.5–3.1 s to playing, of which only ~0.2 s is player rebuild. The floor is the CDN's cold-range latency.
- Bugs to avoid, from BTR's scheduler work:
  - A startup buffer target that kept re-measuring and inflating.
  - Duplicate bytes from cancelled copies never counted.
  - Survivor bias that kept slow nodes "hot". The fix is sampling cancelled transfers, which the port does.

**Hurry mode**
- From BTR PR 11 (not merged upstream):
  - Pick the node by expected finish time.
  - Spread pieces: unknown nodes cost 2× the best per piece; no node takes more than half with ≥ 3 known.
  - A 250–600 ms hedge budget.
  - A node that lost a race before sending gets a higher first-byte estimate; a crawling node's speed is lowered.
  - Piece size `clamp(fastest bps × 0.15 s, 64 KiB, 512 KiB)` in the PR. The port uses the 64 KiB floor in a hurry.
- Built after a cold 4K start took 8.7 s and stalls after jumps on the phone.
- Files: NodeStats, HurryPlacement, PieceDownloader, RangeDownloader. `RipperConfig.hurry` is the switch; `ripper-bench --seeks N --no-hurry` gives the baseline. Not yet measured on the phone.

**Deviations from BTR**
- **Blip strikes heal**: a success clears a node's empty-reply strikes and lifts the node ban they caused.
- **One strike per loss moment**: connections lost before any byte (no status, not a timeout) within 250 ms of the first loss count once, and the window does not stretch. BTR's retry pauses are at least 500 ms, so a node dropping everything is still banned by its second moment.
  - The trigger, on the phone at t+139.08 s: two Akamai -1005 errors 2 ms apart banned it for the rest of the video.
  - Two earlier mid-body -1005s had already used up Akamai's two damaged blocks.
  - Path updates with an unchanged signature do not reset bans.
- **Refusal by a node that has not delivered**: a 4xx of an address other nodes serve drops only that node+address pair, however many such addresses it refuses. BTR blames the node (`cdn-resolver.js` line 133), which had left Akamai banned for the whole video.
- **Damaged copies**: a node that has sent bytes and breaks off without a status, not by timeout, gets its damage recorded from that byte to the end of its MiB.
  - Pieces and backup copies touching the span go to other nodes while any allowed node is left. The init/index fetch does not check it.
  - No strike and no backoff, for up to 2 damaged blocks per node and file; a third is struck and not recorded.
  - A network change forgets all damage.
  - In BTR, the empty replies inside Akamai's gap banned the node after two.
- **Hurry mode as ported**:
  - In a hurry: a startup or seek read, or a segment starting less than 10 s (`hurryAheadSeconds`) ahead, re-checked on every call.
  - Pieces: the 64 KiB floor; the 64 KiB probe head only when no node is known.
  - Placement: by `NodeStats.expectedMs`. An unknown node costs 2× the best × (inflight+1). With ≥ 3 hosts, a node carrying ≥ 2 pieces and more than half of everything in flight gets a large penalty. A single host takes every piece. A full node goes last; an undelivered address loses ties.
  - Hedge budgets:
    - With no first byte yet, a copy starts after `clamp(ttfb×2, 250, 600)` ms (250 ms if ttfb is unknown).
    - After a 1 s gap in arriving bytes.
    - A slow transfer gets a copy once `elapsed ≥ max(400, expected×2)` while under 75% has arrived. An unmeasured node uses the best known candidate's expected time.
    - Outside a hurry the 900 ms delay applies.
  - Later copies go to the candidate expected to finish first (unknown, full and undelivered costs, without the half-share rule); the first copy stays on its placed node. On the phone, copies by speed alone had gone to cosov at 661–673 ms while Akamai answered in 15–24 ms.
  - At most 3 copies, copy k only when copy k−1 is late; no third copy outside a hurry.
  - NodeStats: blend 0.7/0.3; bodies < 32 KiB ignored; a cancelled race loss before any byte raises ttfb; a cancelled transfer is a crawl only after 300 ms and only if slower; a node carries at least 4 connections at full speed; cleared on network change.
- **Busy-node rule**: no first byte in time from a node that is sending other pieces is no strike and no `slow()`. It still counts as a failed request, logged with `busy: true`, and the node's limit drops to what it was receiving. Before this, one cold jump banned Akamai and cosov for the rest of the video (BV1bmpt6WEom at 1:49:47).
- **Full nodes are skipped outside a hurry too**: Akamai (HTTP/1.1, URLSession 8 per host) counts as full at 8 in flight from the start. `PrimaryAssigner` lets a full node sit out. Every copy, the first included, takes its node only once it holds a permit (the first candidate with room, else the first left).
  - Before this, on the phone (2026-10-17, t+122–139 s), threads climbed to 48–64 and Akamai carried 48–61 requests while the mirrors carried 0–8. 38 first-byte timeouts inside URLSession and two stalls followed.
  - The first-byte clock still starts when the request is handed to URLSession.
- **Adopted prefetches survive the player's cancel**: previously AVPlayer's 5 s give-up threw away 7 finished pieces (BV1jt421t7XH). `close()` and a seek (`dropPrefetch`) still cancel them.

**Known environment limits**
- Bilibili's web API refused non-browser requests from the PC in 2026-09. Send Safari-like headers plus the `buvid3`/`buvid4` cookies; the PC speed test can use a saved playurl response.
- Signed media URLs carry a `deadline` (unix seconds); refresh them 5 minutes before it.
- 不喜欢 is an app-signed call (`app.bilibili.com/x/v2/view/dislike`) that needs an access token from the TV QR login (a one-time 确认登录 in a cookie-holding web view) and the TV key pair from `BILI_APP_KEYS`. It has not been tried on the phone. Fallbacks if the server refuses:
  - Send only `access_key` (no appkey/sign).
  - Send the TV-login calls as query parameters with `platform=android` and `mobi_app=android_hd`.
- Unverified until the phone test:
  - favourites `batch-deal` sending both `rid`/`type` and `resources`;
  - follow from a www Origin with a space.bilibili.com referer;
  - history's `type=archive`.

**iOS behaviour the app works around** (app-only, not engine)
- On iOS 27, GeometryReader content froze when the page was pushed from the 推荐 root; the page now measures itself.
- A rotation asked for during a push animation is refused (error 101).
- With the nav bar hidden, UIKit's private `_gestureRecognizer:shouldReceiveEvent:` refuses swipe-back, so `BackSwipe` answers itself.
- Gesture tests need real touches at about 1500 pt/s.
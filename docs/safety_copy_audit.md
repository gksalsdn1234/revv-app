# Safety Copy Audit

Scope: `lib/` user-facing copy screening for top/max speed exposure, G-value emphasis, game-like drive labels, and speed/thrill language. This round only lists findings; production strings are unchanged.

| File:line | Current copy | Exposed surface | Risk | One-line suggestion |
|---|---|---|---|---|
| `lib/screens/lean_drive_screen.dart:838` | `SPEED` + live `km/h` value | Active drive HUD | 높음 | Replace live speed emphasis with route progress, distance remaining, or safety-state copy. |
| `lib/screens/lean_drive_screen.dart:906` | `G METER` | Active drive HUD | 높음 | Replace with calmer handling/vehicle-balance language or hide during active driving. |
| `lib/screens/lean_drive_screen.dart:922` | `PK ${peakG.toStringAsFixed(2)}` | Active drive HUD peak indicator | 높음 | Remove peak chasing language; if needed, move to private diagnostic detail with neutral label. |
| `lib/ui/run_share_metrics.dart:94` | `Peak G` | Run recap/share metric source | 높음 | Replace with non-competitive ride character metric, e.g. `Smoothness` or `Corner rhythm`. |
| `lib/ui/run_share_metrics.dart:99` | `P95 lateral G` | Run recap/share metric source | 높음 | Remove from public/default metrics; keep only private diagnostic export if required. |
| `lib/screens/lean_run_summary_screen.dart:852` | `$sharpCount G이벤트` / `$sharpCount G events` | Run summary map/replay badge | 높음 | Rename to `corner events` or `route moments` without G-value framing. |
| `lib/screens/lean_run_summary_screen.dart:910` | `Peak G` | REVV recap stat tile | 높음 | Replace with route/flow stat or hide from public recap. |
| `lib/screens/lean_run_summary_screen.dart:1399` | `${event.lateralG.toStringAsFixed(2)}G` | Session log event row | 높음 | Show event type/time only; avoid numeric G display in user-facing log. |
| `lib/screens/lean_run_summary_screen.dart:1518` | `P95 LONG G` / `95% 종G` | Session log detail section | 높음 | Move to internal diagnostics or rename to non-scored comfort/braking consistency. |
| `lib/screens/lean_run_summary_screen.dart:1528` | `G-Force analysis` | Session log detail section | 높음 | Replace with `Handling notes` or `Ride smoothness` and remove peak framing. |
| `lib/screens/lean_run_summary_screen.dart:1532` | `Peak ${peakG.toStringAsFixed(2)}G` / `No G peak` | Session log summary | 높음 | Summarize with calm route/flow language instead of peak G. |
| `lib/screens/lean_run_summary_screen.dart:1536` | `MAX LAT G` / `최대 횡G` | Session log detail section | 높음 | Remove max/peak language; if retained internally, gate behind diagnostics. |
| `lib/screens/lean_run_summary_screen.dart:1542` | `MAX LONG G` / `최대 종G` | Session log detail section | 높음 | Remove max/peak language; avoid performance-style ranking. |
| `lib/screens/lean_run_summary_screen.dart:1602` | `0.45G 이상 코너 이벤트가 없었습니다.` / `No corner events above 0.45G.` | Session log empty state | 높음 | Replace threshold copy with `No notable corner events recorded.` |
| `lib/screens/lean_home_screen.dart:611` | `${run.maxLateralG!.toStringAsFixed(2)}G` | Home recent run pill | 높음 | Replace with distance, duration, route rhythm, or weather/context pill. |
| `lib/screens/lean_home_screen.dart:842` | `Best ${bestG.toStringAsFixed(2)}G` | Home stats line | 높음 | Replace `Best G` with total routes, saved runs, or smoothness/flow aggregate. |
| `lib/screens/lean_home_screen.dart:937` | `BEST G` | Home history metric | 높음 | Remove best/record-style G ranking from home summary. |
| `lib/ui/copilot_run_summary.dart:77` | `최고 G` / `Peak G` | Copilot run summary stat | 높음 | Replace with `커브 이벤트` or `Ride smoothness`; avoid peak/superlative framing. |
| `lib/ui/copilot_run_summary.dart:106` | `G 피크` / `G peaks` | Copilot run summary headline | 높음 | Rewrite as route rhythm saved without G-peak wording. |
| `lib/ui/copilot_run_summary.dart:158` | `큰 G 이벤트 없이` / `with no major G events` | Copilot run summary sentence | 높음 | Use `without notable corner events` or `with a calm rhythm`. |
| `lib/ui/copilot_run_summary.dart:164` | `G 이벤트 $sharpCount회와 함께` / `with $sharpCount G events` | Copilot run summary sentence | 높음 | Use `corner events` without G label. |
| `lib/screens/lean_run_summary_screen.dart:2038` | `어택` / `Attack` / `Attaque` | Drive mode legend | 높음 | Rename to a neutral mode such as `Technical`, `Focused`, or `High attention`. |
| `lib/screens/lean_run_summary_screen.dart:2027` | `attack` mapped to danger color | Drive mode legend color | 중간 | Pair the renamed mode with neutral caution styling instead of danger/performance framing. |
| `lib/ui/run_share_metrics.dart:109` | `Max speed` | Internal-only metric object; not in default share card | 중간 | Keep non-public or remove the display object entirely to prevent accidental exposure. |
| `lib/ui/run_share_metrics.dart:73` | `Avg speed` | Recap/share metric source | 중간 | Consider replacing public average speed with moving time, distance, route completion, or flow. |
| `lib/screens/lean_run_summary_screen.dart:1429` | `평균 속도` / `AVG SPEED` | Session log pace row | 중간 | Rename or demote to private detail; public summary can use distance/time only. |
| `lib/ui/copilot_run_summary.dart:145` | `평균 ${session.avgSpeedKmh.toStringAsFixed(0)}km/h` | Copilot run summary sentence | 중간 | Replace with duration/distance context, not speed. |
| `lib/models/revv_route.dart:124` | `EXTREME` | Route difficulty label getter, not currently found in screen usage | 중간 | If surfaced later, replace with `Technical` or `Dense` before exposure. |
| `lib/services/route_loading_policy.dart:828` | `장쾌한 스위퍼 코너가 리듬감 있게 이어지는 루트예요.` | Route recommendation reason | 중간 | Use calmer road-reading language; avoid adrenaline-coded adjectives. |
| `lib/services/route_loading_policy.dart:835` | `코너가 쉼 없이 이어지는 밀도 높은 와인딩 코스예요.` | Route recommendation reason | 중간 | Replace `쉼 없이` with neutral density/spacing wording. |
| `lib/screens/lean_home_screen.dart:1458` | `EARLY EASE-OFF WARNINGS` | Settings/Garage toggle detail | 낮음 | Safety-positive, but consider Korean/French localization and calmer `curve caution` wording. |
| `lib/screens/lean_run_summary_screen.dart:1025` | `Private speed data hidden` | Saved report privacy row | 낮음 | Safe direction; keep, and ensure max speed remains excluded from public surfaces. |
| `lib/screens/lean_run_summary_screen.dart:1776` | `Private speed data hidden` | Privacy/share session log | 낮음 | Safe direction; keep as explicit privacy reassurance. |
| `lib/ui/route_reading_context.dart:75` | `제한속도 표기 $speed · 현장 표지 기준으로 진입하세요.` | Route reading context | 낮음 | Safety-positive; keep unless route context is simplified later. |
| `lib/ui/copilot_briefing.dart:168` | `속도보다 진입 라인 판단이 핵심이에요.` | Route briefing primary advice | 낮음 | Safety-positive because it de-emphasizes speed; keep or make even calmer. |
| `lib/ui/route_detail_copy.dart:138` | `중간 속도 커브 흐름` / `medium-speed curve flow` | Route detail hero reason | 낮음 | Not top speed, but can be replaced with `moderate curve flow` to avoid speed framing. |
| `lib/services/route_loading_policy.dart:745` | `속도보다 노면과 시야를 읽는 재미` | Route recommendation reason | 낮음 | Safety-positive speed de-emphasis; keep or replace `재미` with `판단`. |

High-risk highlights for round 2:

- Active drive HUD still shows live `SPEED`, `G METER`, and peak `PK` values.
- Run summary/home/copilot surfaces repeatedly frame the ride around `Peak G`, `Best G`, numeric G thresholds, and G events.
- Drive mode copy exposes `Attack`/`어택`, which reads as performance/game language.

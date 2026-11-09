# 아르마니여름 랜덤 디펜스 — Godot 프로젝트

Godot 4.x(무료·오픈소스, MIT)로 만든 랜덤 타워디펜스입니다. 지금은 **프로토타입(M1)**: 로비 → 게임(소환·합성·판매·웨이브·보스·승패).

## 실행 (처음 한 번)
1. https://godotengine.org/download 에서 Godot **4.7.x(표준판, .NET 아님)** 를 받아 압축만 풀면 설치 끝(무료).
2. Godot 실행 → **Import** → 이 폴더의 `project.godot` 선택 → 편집기가 열리면 우측 위 ▶(F5).
3. 처음엔 에셋 가져오기(import)로 1~2분 걸립니다. 화면 비율은 세로 720×1280(PC에선 작은 창으로 열림).

## 조작
- 유닛 탭 = 선택(사거리 표시, 같은 등급은 초록 링) / 선택 후 빈 칸 탭 = 이동
- **랜덤 소환**(20코인, 고정) → 같은 등급 3개가 모이면 **합성**(한 단계 위 랜덤 캐릭터, 5% 확률로 2단계 점프, 10번 연속 안 나오면 확정=천장) → **판매**로 코인 환급
- 필드 적 수가 한도(60)를 넘으면 패배, 10·20·30·40웨이브 보스는 60초 안에 못 잡으면 패배

## 폴더
```
게임/
├─ project.godot, export_presets.cfg(웹)
├─ scenes/   lobby.tscn, game.tscn
├─ scripts/  data.gd(JSON 읽기·autoload) sfx.gd(소리·autoload) util.gd game.gd unit.gd enemy.gd projectile.gd lobby.gd
├─ data/     game_data.json, td_atlas.json, sound_atlas.json  ← 엑셀에서 자동 생성
├─ assets/   ← 에셋/ 폴더에서 자동 복사본 (직접 고치지 마세요), fonts/ 는 갈무리(OFL)
├─ web/      shell.html(웹 로딩 화면·진단), static/(복사되는 파일), icon-*.png
└─ .github/workflows/deploy-web.yml  (GitHub Pages 자동 배포)
```

## 데이터/에셋 수정 흐름 (무료 도구만)
| 바꾸고 싶은 것 | 어디서 | 반영 |
|---|---|---|
| 규칙·전투 수치·적·웨이브·보스 | `데이터/캐릭터DB.xlsx` (게임규칙, 전투수치, 적수치, 웨이브구성, 보스 시트) | `도구/게임_데이터_갱신.bat` |
| 캐릭터 색·표정·등급 이름/배율 | 같은 엑셀(캐릭터, 등급 시트) | `도구/전체_생성.bat` → `게임_데이터_갱신.bat` |
| 그림·소리 | `도구/make_*.py` | `전체_생성.bat` → `게임_데이터_갱신.bat` |

## 검증 명령 (Godot 콘솔 실행 파일 사용)
```
godot --headless --path 게임 --import              # 에셋 가져오기(오류 확인)
godot --headless --path 게임 -- --autoplay         # 봇이 끝까지 자동 플레이(밸런스 확인용), 결과 한 줄 출력
godot --path 게임 -- --shot=C:/경로/화면.png        # 자동 플레이 후 실제 화면 저장
```
2026-11-09 기준 봇 결과: 40웨이브 최종 보스에서 시간 초과 패배(사람이 직접 배치·판매하면 더 잘할 수 있음).

## 웹 배포 (무료, GitHub Pages)
**플레이 주소: https://dlwjdskfcl.github.io/jammanbo-defense/** (검색엔진에는 노출되지 않게 noindex 설정)

### 업데이트 흐름
1. 코드·데이터를 고치고 Godot 에서 ▶ 로 먼저 확인.
2. `cd 게임 && git add . && git commit -m "무엇을 바꿨는지" && git push`
3. GitHub 저장소의 **Actions** 탭에서 `deploy-web` 이 초록색 체크(약 2~3분)가 되면 배포 끝.
4. 폰에서 주소를 열어 확인. 이미 열어 둔 적이 있으면 화면 아래에 "새 버전이 있어요 [업데이트]" 가 뜨니 누르세요(안 뜨면 앱을 완전히 닫았다 다시 열기).
5. 문제가 생기면: `git revert HEAD && git push` (직전 변경을 되돌리는 새 커밋 → 자동 재배포).

### 구성
- `web/shell.html` : 로딩 화면(진행바)·'터치해서 시작'(소리/화면유지는 터치 뒤에만 허용)·세로 안내·뒤로가기 보호·새 버전 알림·`?debug=1` 진단. `__BUILD__`/`__DATE__` 는 Actions 가 빌드 번호로 바꿔 넣음.
- `web/static/` : 빌드 결과에 그대로 복사되는 파일(홈 화면 아이콘, robots.txt). `web/icon-*.png` 는 PWA 아이콘(`에셋/07_타이틀` 에서 복사한 것). `web/.gdignore` 가 있어 Godot 이 이 폴더를 가져오지 않음.
- `export_presets.cfg` : 웹 내보내기 설정(스레드 끔, PWA 켬·세로 고정, 교차 출처 격리 헤더 끔, `web/`·문서는 게임 데이터(.pck)에서 제외).
- 서비스 워커(Godot 기본 PWA)가 파일을 기기에 저장해 두 번째부터 빠르게 열고, 새 배포마다 캐시 이름이 바뀌어 예전 파일이 남지 않습니다.
- 처음 열 때 약 10MB(.wasm 은 gzip 으로 줄어서 전송됨, 압축 전 39.5MB) + 게임 데이터 1.8MB 를 받습니다. GitHub Pages 는 gzip 은 주지만 brotli 는 주지 않습니다.
- Cloudflare Pages 는 파일 1개 25 MiB 제한이라 .wasm 이 올라가지 않아 쓰지 않습니다.

### 진단
- 주소 끝에 `?debug=1` → 화면 아래에 빌드 번호·FPS·자바스크립트/Godot 오류 로그 표시. 평소에도 브라우저 콘솔에 `[아르마니여름] build 번호 (날짜)` 가 찍힙니다.
- 배포된 빌드 번호: `https://dlwjdskfcl.github.io/jammanbo-defense/version.json`

### 문제 해결
| 증상 | 원인/해결 |
|---|---|
| Actions 가 빨간색 | 실행을 눌러 "에셋 가져오기"/"웹 내보내기" 단계 로그 확인. `SCRIPT ERROR`·`Parse Error` 면 코드 오류 → Godot 에서 ▶ 로 재현. 빌드 번호/파일 없음 오류면 `export_presets.cfg`·`web/shell.html` 확인 |
| `deploy-pages` 만 실패 | 저장소 Settings → Pages → Source 가 "GitHub Actions" 인지 확인 |
| 예전 화면이 계속 보임 | 앱/탭을 완전히 닫고 다시 열기, 또는 주소 끝에 `?x=2`. 최대 10분(GitHub 캐시) 걸릴 수 있음 |
| 하얀/까만 화면에서 멈춤 | 최신 Chrome/Safari 로 열기. `?debug=1` 로 오류 확인. 저사양 폰은 WebGL2 필요 |
| 진행이 저장 안 됨 | 시크릿(비공개) 모드이거나 사이트 데이터 삭제를 막은 경우. 로딩 화면에 경고가 뜹니다 |
| 소리가 안 남 | '터치해서 시작'을 눌러야 소리가 켜집니다. 무음 모드(iPhone 측면 스위치)도 확인 |

## 공개 저장소 주의
이 저장소는 **공개**입니다. 이 폴더(`게임/`)만 올리세요. 상위 폴더에는 다른 게임 스크린샷(참고용)·원본 사진이 있어 공개하면 안 됩니다. 개인 이메일·토큰·키를 코드에 넣지 마세요(커밋 작성자는 noreply 이메일).

## 라이선스
엔진 Godot(MIT), 글꼴 갈무리(SIL OFL 1.1) 등 — 자세한 고지는 [THIRD_PARTY.md](THIRD_PARTY.md).

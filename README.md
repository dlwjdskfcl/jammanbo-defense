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
└─ .github/workflows/deploy-web.yml  (GitHub Pages 자동 배포 초안)
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

## 웹 배포 (무료)
1. Godot 편집기 → 프로젝트 → 내보내기 → Web 선택(처음엔 "내보내기 템플릿 관리"에서 4.7.x 설치) → `build/index.html` 로 내보내기.
2. `build/` 폴더를 **GitHub Pages** 에 올리면 폰 브라우저에서 바로 실행됩니다. (Cloudflare Pages 는 파일 1개 25 MiB 제한이라 Godot 의 .wasm(약 39MB)이 올라가지 않아 쓰지 않습니다.)
3. 자동 배포: 이 폴더를 GitHub 저장소로 올리고 Pages 소스를 "GitHub Actions"로 설정하면 `deploy-web.yml` 이 빌드·배포(초안, 미검증).
- 스레드 지원은 끄고(`variant/thread_support=false`) 내보내서 별도 서버 헤더 없이 동작하게 했습니다.
- ⚠️ 이 저장소에는 **게임 폴더만** 올리세요. 상위 폴더에는 다른 게임 스크린샷(참고용)이 있어 공개하면 안 됩니다.

## 라이선스 메모
- 엔진: Godot (MIT). 글꼴: 갈무리 Galmuri (SIL OFL 1.1, `assets/fonts/Galmuri_LICENSE_OFL.txt`).

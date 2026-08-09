#!/usr/bin/env bash
#
# feature → dev → main 흐름을 묶은 하네스.
#
#   ./scripts/flow.sh new <이름>    dev 최신화 후 feature/<이름> 생성
#   ./scripts/flow.sh ship          현재 feature → 빌드 검증 → dev 머지 → push
#   ./scripts/flow.sh release       dev → main 머지 → push
#   ./scripts/flow.sh status        지금 상태
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
info() { printf '%s▸%s %s\n' "$GREEN" "$OFF" "$1"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$OFF" "$1"; }
die()  { printf '%s✗%s %s\n' "$RED" "$OFF" "$1" >&2; exit 1; }

current_branch() { git rev-parse --abbrev-ref HEAD; }

require_clean() {
  if [ -n "$(git status --porcelain)" ]; then
    git -c core.quotepath=false status --short
    die "커밋되지 않은 변경이 있습니다. 커밋하거나 stash 하세요."
  fi
}

# dev 이후 변경된 서비스만 골라서 빌드한다. 없으면 빌드 생략.
build_changed() {
  local base=$1 changed built=0
  changed=$(git diff --name-only "$base"...HEAD -- services/ || true)

  for svc in order delivery; do
    if printf '%s\n' "$changed" | grep -q "^services/$svc/"; then
      info "빌드: $svc"
      ( cd "$ROOT/services/$svc" && ./gradlew build -x test --no-daemon -q --console=plain ) \
        || die "$svc 빌드 실패 — 머지 중단"
      built=1
    fi
  done

  [ "$built" = "0" ] && info "변경된 서비스 없음 — 빌드 생략 (문서/설정만 바뀜)"
  return 0
}

cmd_new() {
  local name=${1:-}
  [ -n "$name" ] || die "사용법: flow.sh new <이름>   예) flow.sh new order-create-api"
  require_clean

  info "dev 최신화"
  git switch dev -q && git pull --ff-only -q

  local branch="feature/$name"
  git switch -c "$branch" -q
  info "생성됨: $branch"
  printf '%s작업하고 커밋한 뒤 ./scripts/flow.sh ship%s\n' "$DIM" "$OFF"
}

cmd_ship() {
  local branch; branch=$(current_branch)
  case "$branch" in
    feature/*|fix/*|refactor/*|docs/*|chore/*) ;;
    *) die "작업 브랜치에서 실행하세요. 지금: $branch" ;;
  esac
  require_clean

  info "dev 최신화"
  git fetch origin -q
  git switch dev -q && git pull --ff-only -q
  git switch "$branch" -q

  # dev 가 앞서 있으면 먼저 합쳐서 충돌을 여기서 해결한다
  if ! git merge-base --is-ancestor dev "$branch"; then
    info "dev 변경사항을 $branch 에 먼저 반영"
    git merge dev -q -m "Merge dev into $branch" || die "충돌 발생 — 해결 후 다시 ship"
  fi

  build_changed dev

  info "dev ← $branch 머지"
  git switch dev -q
  git merge --no-ff "$branch" -q -m "Merge $branch into dev"
  git push origin dev -q
  info "dev push 완료"

  printf '%s브랜치 %s 를 삭제할까요? [y/N] %s' "$YELLOW" "$branch" "$OFF"
  read -r ans || ans=""   # 비대화형(EOF)이면 삭제하지 않음
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    git branch -d "$branch" -q
    git push origin --delete "$branch" -q 2>/dev/null || true
    info "삭제됨"
  fi

  printf '%s배포하려면 ./scripts/flow.sh release%s\n' "$DIM" "$OFF"
}

cmd_release() {
  require_clean
  info "최신화"
  git fetch origin -q
  git switch dev -q && git pull --ff-only -q
  git switch main -q && git pull --ff-only -q

  if git merge-base --is-ancestor dev main; then
    warn "main 이 이미 dev 를 포함합니다. 올릴 게 없습니다."
    return 0
  fi

  printf '\n%s이번에 main 으로 가는 커밋:%s\n' "$DIM" "$OFF"
  git log --oneline main..dev
  printf '\n%s진행할까요? [y/N] %s' "$YELLOW" "$OFF"
  read -r ans || ans=""   # 비대화형(EOF)이면 취소
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { warn "취소"; git switch dev -q; return 0; }

  build_changed main

  git merge --no-ff dev -q -m "Merge dev into main"
  git push origin main -q
  info "main push 완료"
  git switch dev -q
}

cmd_status() {
  printf '%s현재 브랜치%s  %s\n' "$DIM" "$OFF" "$(current_branch)"
  printf '%s미커밋%s      %s개\n' "$DIM" "$OFF" "$(git status --porcelain | wc -l | tr -d ' ')"
  git fetch origin -q 2>/dev/null || true
  printf '%sdev..main%s   ' "$DIM" "$OFF"
  local n; n=$(git rev-list --count main..dev 2>/dev/null || echo '?')
  printf 'dev 가 main 보다 %s커밋 앞\n' "$n"
  printf '\n'
  git log --oneline --graph --all -8
}

case "${1:-}" in
  new)     shift; cmd_new "$@" ;;
  ship)    cmd_ship ;;
  release) cmd_release ;;
  status)  cmd_status ;;
  *)
    sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac

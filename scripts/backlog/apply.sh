#!/usr/bin/env bash
# Apply docs/backlog/migration-plan.md. Run from the worktree root. Usage: apply.sh <phase>
S="${S:-${TMPDIR:-/tmp}}"
# phases: labels | issues | subissues | board
set -uo pipefail
R=smart-campus-ai/smart-campus-ai; O=smart-campus-ai; P=1
PLAN=docs/backlog/migration-plan.md
MAP="$S/map.tsv"

trim() { sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }

# Table rows: ID | Action | Issue | Titre | Labels | Epic | Priorité | Taille | Rôle | Assignés | Dépendances | Corps
rows() {
  grep -E '^\|[[:space:]]*(E[0-9]|EN-|US|RF|NFR)' "$PLAN" | grep -vE '^\|[[:space:]]*ID[[:space:]]*\|' |
  while IFS='|' read -r _ id act num title labels epic prio size role assg deps body _; do
    printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
      "$(echo "$id"|trim)" "$(echo "$act"|trim)" "$(echo "$num"|trim|tr -d '#')" "$(echo "$title"|trim)" \
      "$(echo "$labels"|trim|tr -d '`'|sed 's/, */,/g')" "$(echo "$epic"|trim)" "$(echo "$prio"|trim)" \
      "$(echo "$size"|trim)" "$(echo "$role"|trim)" "$(echo "$body"|trim|tr -d '`')"
  done
}

case "$1" in
dry)
  rows | tr '\037' '\t' > "$S"/rows.tsv
  cut -f2 "$S"/rows.tsv | sort | uniq -c
  awk -F'\t' '$2=="UPDATE"{printf "%s=#%s ", $1, $3} END{print ""}' "$S"/rows.tsv
  cut -f1 "$S"/rows.tsv | sort | uniq -d | sed 's/^/DUP /'
  cut -f10 "$S"/rows.tsv | while read -r f; do [ -f "$f" ] || echo "MISSING $f"; done
  head -3 "$S"/rows.tsv ;;
labels)
  for l in accessibility bug documentation duplicate enhancement "good first issue" "help wanted" invalid question wontfix; do
    gh label delete "$l" -R $R --yes 2>&1 | tail -1
  done
  # name<TAB>color<TAB>description lines from the plan's label table: | `name` | `#hex` | desc |
  grep -E '^\|[[:space:]]*`?(type|area|role|priority|size|status)/|^\|[[:space:]]*`?(drift|dependencies|security)`?[[:space:]]*\|' "$PLAN" |
  while IFS='|' read -r _ name color desc _; do
    name=$(echo "$name"|trim|tr -d '`'); color=$(echo "$color"|trim|tr -d '`#'); desc=$(echo "$desc"|trim)
    gh label create "$name" -R $R --color "$color" --description "$desc" --force >/dev/null && echo "label $name"
  done ;;
issues)
  : > "$MAP"
  rows | while IFS=$'\037' read -r id act num title labels epic prio size role body; do
    case "$act" in
      CREATE)
        url=$(gh issue create -R $R --title "$title" --body-file "$body" --label "$labels" </dev/null) || { echo "FAIL $id"; continue; }
        num=${url##*/} ;;
      UPDATE)
        gh issue edit "$num" -R $R --title "$title" --body-file "$body" --add-label "$labels" </dev/null >/dev/null || { echo "FAIL $id"; continue; } ;;
      *) continue ;;
    esac
    printf '%s\t%s\n' "$id" "$num" >> "$MAP"; echo "$act $id #$num"
  done ;;
subissues)
  rows | while IFS=$'\037' read -r id act num title labels epic prio size role body; do
    [ -n "$epic" ] && [ "$act" != "KEEP CLOSED" ] || continue
    c=$(awk -F'\t' -v k="$id" '$1==k{print $2}' "$MAP"); p=$(awk -F'\t' -v k="$epic" '$1==k{print $2}' "$MAP")
    [ -n "$c" ] && [ -n "$p" ] || { echo "SKIP $id"; continue; }
    cid=$(gh api repos/$R/issues/$c --jq .id)
    gh api -X POST repos/$R/issues/$p/sub_issues -F sub_issue_id="$cid" </dev/null >/dev/null && echo "$id -> $epic"
  done ;;
board)
  F=$(gh project field-list $P --owner $O --format json)
  fid() { echo "$F" | jq -r --arg n "$1" '.fields[]|select(.name==$n).id'; }
  oid() { echo "$F" | jq -r --arg n "$1" --arg o "$2" '.fields[]|select(.name==$n).options[]|select(.name==$o).id'; }
  PID=$(gh project view $P --owner $O --format json --jq .id)
  set_opt() { local o; o=$(oid "$2" "$3"); [ -n "$o" ] && gh project item-edit --project-id "$PID" --id "$1" --field-id "$(fid "$2")" --single-select-option-id "$o" </dev/null >/dev/null; }
  cap() { echo "$1" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}'; }
  rows | while IFS=$'\037' read -r id act num title labels epic prio size role body; do
    n=$(awk -F'\t' -v k="$id" '$1==k{print $2}' "$MAP"); [ -n "$n" ] || continue
    item=$(gh project item-add $P --owner $O --url "https://github.com/$R/issues/$n" --format json --jq .id </dev/null) || continue
    p=$(cap "$prio"); [ "$p" = "Wont" ] || [ "$p" = "Won't" ] && p="Won't"
    case "$id" in EN-01|EN-02|EN-04|EN-71) st=Ready ;; *) st=Backlog ;; esac
    set_opt "$item" Status "$st"; set_opt "$item" Priority "$p"
    [ -n "$epic" ] && set_opt "$item" Epic "$epic" || set_opt "$item" Epic "$id"
    set_opt "$item" Role "$(echo "${role%%,*}"|trim|tr a-z A-Z)"; set_opt "$item" Size "$(echo "$size"|tr a-z A-Z)"
    echo "board $id"
  done ;;
esac

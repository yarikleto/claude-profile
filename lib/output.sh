# output.sh — Terminal colors and logging

if [[ -t 1 ]]; then
  RED='\033[0;31m'  GREEN='\033[0;32m'  YELLOW='\033[0;33m'
  BLUE='\033[0;34m' CYAN='\033[0;36m'   MAGENTA='\033[0;35m'
  BOLD='\033[1m'    DIM='\033[2m'       NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA=''
  BOLD='' DIM='' NC=''
fi

info()  { echo -e "${BLUE}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

# Styled profile name for use in messages
_pname() { echo -e "${CYAN}${BOLD}$1${NC}"; }

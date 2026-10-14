#!/usr/bin/env bash
# Rebuild the pinned simulation stack (docs/adr/0001-pin-isaaclab-v2.3.2.md) in one pass:
# IsaacLab and unitree_model checkouts at their pinned commits, a fresh conda env, Isaac Sim 5.1.0,
# IsaacLab v2.3.2 and this repo, then verify the result against env_isaaclab_v232.lock.txt.
#
# Usage:   scripts/setup/install_env.sh
# Options (environment variables):
#   ENV_NAME   conda env to create (default: env_isaaclab_v232); must not exist yet
#   WORKSPACE  directory holding IsaacLab/ and unitree_model/ (default: parent of this repo);
#              missing checkouts are cloned, existing ones must be at the pinned commit
# Requires: conda, git, git-lfs, NVIDIA driver 580 (ADR 0001). Prompts once for the Isaac Sim EULA
# (skipped if OMNI_KIT_ACCEPT_EULA=YES, which then has to be set for every later run as well).
#
# Not done here: `activate-global-python-argcomplete` from `unitree_rl_lab.sh -i` (a shell-wide,
# interactive change that only enables tab completion), and UNITREE_MODEL_DIR in
# source/unitree_rl_lab/unitree_rl_lab/assets/robots/unitree.py (see TODO.md).

set -eo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SETUP=$REPO/scripts/setup
WORKSPACE=${WORKSPACE:-$(dirname "$REPO")}
ENV_NAME=${ENV_NAME:-env_isaaclab_v232}
ISAACLAB_DIR=$WORKSPACE/IsaacLab
UNITREE_MODEL_DIR=$WORKSPACE/unitree_model
LOCK=$SETUP/env_isaaclab_v232.lock.txt

# Pins (ADR 0001)
ISAACLAB_URL=https://github.com/isaac-sim/IsaacLab.git
ISAACLAB_TAG=v2.3.2
ISAACLAB_COMMIT=37ddf626871758333d6ed89cf64ad702aef127d0
ISAACLAB_BRANCH=pin/v2.3.2
UNITREE_MODEL_URL=https://huggingface.co/datasets/unitreerobotics/unitree_model
UNITREE_MODEL_COMMIT=323e350252b9c3aee9c40acbfdad84f6ce46a5ac
PIP_VERSION=26.2.1
TORCH_INDEX=https://download.pytorch.org/whl/cu128
ISAACSIM_SPEC="isaacsim[all,extscache]==5.1.0"
DRIVER_BRANCH=580
# The one accepted `pip check` conflict (ADR 0001, Consequences).
KNOWN_PIP_CHECK="fastapi 0.115.7 has requirement starlette<0.46.0,>=0.40.0, but you have starlette 0.49.1."

log() { echo "[setup] $*"; }
die() {
    echo "[setup] ERROR: $*" >&2
    exit 1
}

# --- preflight -------------------------------------------------------------------------------------
for cmd in conda git git-lfs nvidia-smi; do
    command -v "$cmd" > /dev/null || die "'$cmd' not found on PATH"
done
driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
log "NVIDIA driver: $driver"
[[ $driver == "$DRIVER_BRANCH".* ]] ||
    log "WARNING: driver is not $DRIVER_BRANCH.x; Isaac Sim 5.1 segfaulted on 615 on an RTX 5080 (ADR 0001)"

source "$(conda info --base)/etc/profile.d/conda.sh"
if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    die "conda env '$ENV_NAME' already exists; remove it first: conda env remove -n $ENV_NAME"
fi

# --- source checkouts --------------------------------------------------------------------------------
if [[ ! -d $ISAACLAB_DIR ]]; then
    log "cloning IsaacLab $ISAACLAB_TAG into $ISAACLAB_DIR"
    git clone "$ISAACLAB_URL" "$ISAACLAB_DIR"
    git -C "$ISAACLAB_DIR" switch -c "$ISAACLAB_BRANCH" "$ISAACLAB_TAG"
fi
head=$(git -C "$ISAACLAB_DIR" rev-parse HEAD)
[[ $head == "$ISAACLAB_COMMIT" ]] ||
    die "IsaacLab at $head, expected $ISAACLAB_TAG ($ISAACLAB_COMMIT): git -C $ISAACLAB_DIR switch -c $ISAACLAB_BRANCH $ISAACLAB_TAG"
[[ -z $(git -C "$ISAACLAB_DIR" status --porcelain --untracked-files=no) ]] ||
    die "IsaacLab has local modifications to tracked files"

if [[ ! -d $UNITREE_MODEL_DIR ]]; then
    log "cloning unitree_model @ ${UNITREE_MODEL_COMMIT:0:7} into $UNITREE_MODEL_DIR"
    GIT_LFS_SKIP_SMUDGE=1 git clone "$UNITREE_MODEL_URL" "$UNITREE_MODEL_DIR"
    git -C "$UNITREE_MODEL_DIR" checkout -q "$UNITREE_MODEL_COMMIT"
    git -C "$UNITREE_MODEL_DIR" lfs install --local
    git -C "$UNITREE_MODEL_DIR" lfs pull
fi
head=$(git -C "$UNITREE_MODEL_DIR" rev-parse HEAD)
[[ $head == "$UNITREE_MODEL_COMMIT" ]] || die "unitree_model at $head, expected $UNITREE_MODEL_COMMIT"
# `git lfs ls-files` marks files whose content is not checked out (still pointer stubs) with '-'.
stubs=$(git -C "$UNITREE_MODEL_DIR" lfs ls-files | grep -c ' - ' || true)
[[ $stubs -eq 0 ]] || die "unitree_model has $stubs LFS pointer stubs: git -C $UNITREE_MODEL_DIR lfs pull"

# --- conda env and Python packages ------------------------------------------------------------------
log "creating conda env $ENV_NAME from $ISAACLAB_DIR/environment.yml"
conda env create -y -f "$ISAACLAB_DIR/environment.yml" -n "$ENV_NAME"
conda activate "$ENV_NAME"
log "python: $(python --version) at $(command -v python)"

# PIP_BUILD_CONSTRAINT needs a recent pip; pin it before exporting the constraints.
python -m pip install "pip==$PIP_VERSION"

# Constraints = policy caps + every locked version, except direct-URL entries (IsaacLab requests a git
# branch/tag, not the locked commit; the final diff checks them) and starlette (Isaac Sim's fastapi needs
# <0.46 when isaacsim installs; IsaacLab's own ==0.49.1 pin replaces it later -- the accepted conflict).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
{
    cat "$SETUP/constraints.txt"
    grep -vE '^\s*(#|$)| @ |^starlette==' "$LOCK"
} > "$tmp/constraints.txt"
export PIP_CONSTRAINT=$tmp/constraints.txt
export PIP_BUILD_CONSTRAINT=$SETUP/build-constraints.txt

log "installing torch stack (cu128)"
python -m pip install torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 --index-url "$TORCH_INDEX"
python -m pip install "wheel<0.46"

log "installing $ISAACSIM_SPEC"
python -m pip install "$ISAACSIM_SPEC" --extra-index-url https://pypi.nvidia.com

# Prompts unless OMNI_KIT_ACCEPT_EULA is set; on "No" it exits 0, so check the outcome explicitly.
python -c "from isaacsim.kit import kit_app; kit_app.check_eula()"
# Same location kit_app.check_eula() writes to (isaacsim.kit is a namespace package, so use kit_app's path).
eula_marker=$(python -c "from isaacsim.kit import kit_app; import os; print(os.path.join(os.path.dirname(os.path.realpath(kit_app.__file__)), 'EULA_ACCEPTED'))")
[[ -f $eula_marker || ${OMNI_KIT_ACCEPT_EULA,,} =~ ^(y|yes|1)$ ]] || die "Isaac Sim EULA not accepted"

cd "$ISAACLAB_DIR"
# Run from inside the target env: setup_conda_env deletes ${CONDA_PREFIX}'s hook first (docs/LESSONS.md).
./isaaclab.sh --conda "$ENV_NAME"
# Re-activate to pick up the hooks just written (ISAACLAB_PATH, libgomp preload). errexit is off around it:
# the new deactivate hook runs `unalias isaaclab`, which fails in this shell because the env was activated
# before the alias existed, and under `set -e` that failure in a sourced hook aborts the script.
set +e
conda deactivate
conda activate "$ENV_NAME"
set -e
[[ $CONDA_PREFIX == "$(conda info --base)/envs/$ENV_NAME" && -n $ISAACLAB_PATH ]] ||
    die "re-activating $ENV_NAME failed (CONDA_PREFIX=$CONDA_PREFIX, ISAACLAB_PATH=$ISAACLAB_PATH)"

log "installing IsaacLab $ISAACLAB_TAG extensions and RL frameworks"
./isaaclab.sh --install

log "installing unitree_rl_lab (editable)"
python -m pip install -e "$REPO/source/unitree_rl_lab"
# Conda activation hook from upstream `unitree_rl_lab.sh -i`; the "" argument keeps the sourced script's
# case statement from seeing this script's arguments.
source "$REPO/unitree_rl_lab.sh" ""
_ut_setup_conda_env

# --- verification ----------------------------------------------------------------------------------
log "verifying"
check=$(python -m pip check 2>&1 || true)
unexpected=$(grep -vxF "$KNOWN_PIP_CHECK" <<< "$check" | grep -v '^$' || true)
[[ -z $unexpected ]] || die "pip check reported unexpected conflicts:"$'\n'"$unexpected"

if ! freeze_diff=$(diff <(grep -vE '^\s*(#|$)' "$LOCK" | sort) <(python -m pip freeze --exclude-editable | sort)); then
    die "installed packages differ from $LOCK (< lock, > installed):"$'\n'"$freeze_diff"
fi

python - << 'EOF'
import torch

conv = torch.nn.Conv2d(3, 8, 3).cuda()
out = conv(torch.randn(1, 3, 16, 16, device="cuda"))
assert out.isfinite().all(), "non-finite conv output"
print(f"[setup] torch {torch.__version__}, cuDNN {torch.backends.cudnn.version()}, NCCL {torch.cuda.nccl.version()}: OK")
EOF

log "done: env '$ENV_NAME' matches $LOCK. Activate with: conda activate $ENV_NAME"

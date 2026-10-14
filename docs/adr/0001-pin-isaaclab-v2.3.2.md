# ADR 0001: Pin the simulation stack to IsaacLab v2.3.2

- **Status:** Accepted
- **Date:** 2026-10-14

## Context

This fork tracks upstream `unitreerobotics/unitree_rl_lab` `main` at `4960b84` (2025-11-19), which targets IsaacLab 2.3.0 and Isaac Sim 5.1.0 (README badges, commit `4e08d96`). Its agent configs use the rsl-rl `policy` schema (`RslRlPpoActorCriticCfg`), which only rsl-rl < 4.0 accepts natively.

The local IsaacLab checkout had been on `main` (`b0542fe2d`, 33 commits past `v2.3.2`), whose `VERSION` file still reads `2.3.2`. Commit `47c9f95ee` on `main` raised the pin to `rsl-rl-lib==5.0.1`, and training failed in `rsl_rl/algorithms/ppo.py` with `KeyError: 'class_name'` because rsl-rl >= 4.0 expects separate `actor`/`critic` model configs. Installing from `main` also left the conda env with packages outside Isaac Sim 5.1's pins: `stable-baselines3 2.9.0` (requires `torch>=2.8`, Isaac Sim 5.1 uses `2.7.0+cu128`), `skrl 2.1.0`, and `click`/`psutil` versions above `isaacsim-kernel`'s exact pins (observed with `pip check`).

Release landscape on 2026-10-14 (from `git ls-remote`/tags and `pypi.nvidia.com`):

- Isaac Sim GA: 5.1.0, 6.0.x, 6.1.0, 6.2.0. Isaac Sim 6.x wheels are published for CPython 3.12 only.
- IsaacLab latest GA: `v2.3.2` (2026-01-29), for Isaac Sim 5.1 with `rsl-rl-lib==3.1.2`. IsaacLab 3.0 exists only as pre-release tags; the newest, `v3.0.0-EA` (2026-09-16), pins Isaac Sim 6.1.0 and `rsl-rl-lib==5.4.1`.
- unitree_rl_lab: IsaacLab 3.0 support lives on upstream branch `isaaclab3.0` (`2522f89`, 2026-05-25), built against the 3.0 beta, not merged into `main`.

The goal is a recent but stable environment to learn the components on, with a later migration once the newer stack settles.

## Decision

Pin every component to the newest GA IsaacLab release and the versions that release specifies:

| Component | Pin | Notes |
|---|---|---|
| NVIDIA driver | `nvidia-driver-580-open` 580.178.04 | Isaac Sim 5.1 segfaulted on this machine (RTX 5080) with driver 615-open; it starts on 580.178.04 (observed 2026-10-14). |
| Python | 3.11 | IsaacLab v2.3.2 `environment.yml`. |
| Isaac Sim | `isaacsim[all,extscache]==5.1.0` | pip, from `pypi.nvidia.com`. |
| PyTorch | `torch==2.7.0`, `torchvision==0.22.0` (cu128) | IsaacLab v2.3.2 `isaaclab.sh` `ensure_cuda_torch` (x86_64). |
| IsaacLab | tag `v2.3.2` (`37ddf6268`), local branch `pin/v2.3.2` | Installed with `./isaaclab.sh --install`. |
| rsl-rl-lib | 3.1.2 | Pinned by IsaacLab v2.3.2 `isaaclab_rl`. |
| unitree_rl_lab | this fork, upstream `main` `4960b84` + local fixes | |
| unitree_model | HuggingFace `unitreerobotics/unitree_model` @ `323e350` | Requires `git-lfs`; see `docs/LESSONS.md`. |

Several requirements in IsaacLab v2.3.2 have no upper bound and now resolve to versions that break the stack. `./isaaclab.sh --install` is therefore run with two constraint files from this repo:

- `scripts/setup/constraints.txt` (`PIP_CONSTRAINT`): torch 2.7.0 stack, `stable-baselines3<2.9` (2.9 needs torch >= 2.8), `skrl<2` (v2.3.2's integration predates skrl 2.0), `wheel<0.46`, and Isaac Sim's exact `click`/`idna`/`psutil` pins.
- `scripts/setup/build-constraints.txt` (`PIP_BUILD_CONSTRAINT`): `setuptools<81`, without which `flatdict==4.0.1` (pinned by v2.3.2, sdist only) fails to build because current setuptools no longer ships `pkg_resources`. pip 26.2.1 does not apply `PIP_CONSTRAINT` to build environments (observed).

Each entry carries its reason in the file. Exact versions of every installed Python package are recorded in `scripts/setup/env_isaaclab_v232.lock.txt`. The conda env is named `env_isaaclab_v232`.

## Alternatives considered

1. **Stay on IsaacLab `main` with rsl-rl 5 and patch the unitree scripts** with `handle_deprecated_rsl_rl_cfg`. Rejected: training ran (3-iteration smoke test), but `main` moves continuously, and rsl-rl 4/5 also changed the model classes, checkpoint layout and export API, so `play.py` and the deploy export needed rewrites against a combination upstream never tested.
2. **IsaacLab `v3.0.0-EA` + Isaac Sim 6.1 + upstream `isaaclab3.0` branch.** Rejected for now: nothing in IsaacLab 3.0 is GA, the unitree branch targets the 3.0 beta rather than the EA, it needs a Python 3.12 env, and Isaac Sim 6 on this GPU/driver is unverified.
3. **IsaacLab `v2.3.0`, the exact upstream target.** Rejected in favour of `v2.3.2`, the latest patch release on the same line with the same rsl-rl `policy` schema. Its core (`isaaclab` 0.54.2) is close to the 0.54.4 already exercised by the smoke test on `main`.
4. **Repair the existing `env_isaaclab` in place.** Rejected: the lock file would have recorded the drift from `main` instead of what v2.3.2 resolves to.

## Consequences

- `scripts/rsl_rl/play.py` imports `get_published_pretrained_checkpoint` from `isaaclab_rl.utils`. IsaacLab moved it there from `isaaclab.utils` in v2.3.2, so upstream's `play.py` fails to import on v2.3.2.
- `pip check` reports one accepted conflict: `fastapi 0.115.7` (from Isaac Sim) wants `starlette<0.46`, while IsaacLab v2.3.2 pins `starlette==0.49.1` (`source/isaaclab/setup.py:40`, a security update). IsaacLab's pin is kept, which may affect Isaac Sim's fastapi-based services. Go2 training (3 iterations), `play.py` checkpoint loading and ONNX/JIT export all ran with it (headless, 2026-10-14).
- The env was built in several passes while the constraints were being worked out. Leftovers from an unconstrained pass were removed, and the lock was frozen from the cleaned env. Rebuilding from the constraint files in a single pass has not been done yet (see `TODO.md`).
- IsaacLab 2.3 looks frozen: `release/2.3.0` was last updated 2025-12-02. That is inferred from branch activity, not announced; expect no further fixes on this line.
- Revisit this ADR when IsaacLab 3.0.0 is released as GA **and** upstream unitree_rl_lab merges its IsaacLab 3.0 support into `main`.

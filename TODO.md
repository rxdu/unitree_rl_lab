# TODO

## Environment (ADR 0001: IsaacLab v2.3.2 pin)

- [ ] Make `UNITREE_MODEL_DIR` portable across machines: `source/unitree_rl_lab/unitree_rl_lab/assets/robots/unitree.py:20` holds a machine-local absolute path (kept uncommitted).
- [x] `scripts/setup/install_env.sh` rebuilds `env_isaaclab_v232` in one pass and verifies it against `env_isaaclab_v232.lock.txt`. Verified from scratch on rdu-c34, 2026-10-14 (sources cloned, env built, `pip freeze` == lock, Go2 train/play/export pass).
- [ ] Run `scripts/setup/install_env.sh` on a second machine; a freeze mismatch there would show platform- or time-dependent resolution (e.g. the `rl_games` git branch moving past the locked commit).
- [x] Remove the old `env_isaaclab` conda env (built from IsaacLab `main`, rsl-rl 5). Removed 2026-10-14.
- [ ] Decide whether to `apt-mark hold nvidia-driver-580-open` so an upgrade cannot bring back the driver-615 segfault.
- [ ] Revisit ADR 0001 when IsaacLab 3.0.0 is GA and upstream merges its `isaaclab3.0` branch into `main`. Note for that migration: rsl-rl 3.1.2 already warns that the agent configs lack `obs_groups` `policy`/`critic` keys ("will be removed in a future version"; observed in `play.py` output).

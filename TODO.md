# TODO

## Environment (ADR 0001: IsaacLab v2.3.2 pin)

- [ ] Make `UNITREE_MODEL_DIR` portable across machines: `source/unitree_rl_lab/unitree_rl_lab/assets/robots/unitree.py:20` holds a machine-local absolute path (kept uncommitted).
- [ ] Add a `scripts/setup/` install script that rebuilds `env_isaaclab_v232` in one pass (conda env from IsaacLab `environment.yml` → torch cu128 → `isaacsim[all,extscache]==5.1.0` → `isaaclab.sh --conda` from inside the env → `isaaclab.sh --install` with `constraints.txt`/`build-constraints.txt` → `pip install -e source/unitree_rl_lab`). Verify it from scratch on a second machine and diff `pip freeze` against `env_isaaclab_v232.lock.txt`. The current env was built in several passes and cleaned (ADR 0001, Consequences).
- [ ] Remove the old `env_isaaclab` conda env (built from IsaacLab `main`, rsl-rl 5) once `env_isaaclab_v232` has been used for a real training run. Its editable installs now point at the v2.3.2 sources, so it is inconsistent and should not be used.
- [ ] Decide whether to `apt-mark hold nvidia-driver-580-open` so an upgrade cannot bring back the driver-615 segfault.
- [ ] Revisit ADR 0001 when IsaacLab 3.0.0 is GA and upstream merges its `isaaclab3.0` branch into `main`.

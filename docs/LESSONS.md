# Lessons

### IsaacLab `main` is not a release
- **Pattern:** The IsaacLab checkout tracked `main`, whose `VERSION` file still read `2.3.2` while it pinned `rsl-rl-lib==5.0.1`. Training failed with `KeyError: 'class_name'` in rsl-rl's PPO, and the env picked up packages that conflict with Isaac Sim 5.1 (SB3 2.9 needs torch >= 2.8).
- **Correction:** Pin IsaacLab to a release tag on a local branch (see `docs/adr/0001-pin-isaaclab-v2.3.2.md`). Check `git describe --tags` or `git rev-list <tag>..HEAD --count`, not `VERSION`. Run `pip check` after every `./isaaclab.sh --install`.
- **Context:** IsaacLab source install, rsl_rl, pip/conda env.

### unitree_model clones silently without git-lfs
- **Pattern:** Cloning `huggingface.co/datasets/unitreerobotics/unitree_model` without `git-lfs` installed succeeds, but every `configuration/*_base.usd` (the geometry layer) is a ~130-byte LFS pointer. The top-level `go2.usd` is small enough to be real, so the failure appears one layer down at scene load.
- **Correction:** Install `git-lfs` before cloning, or run `git lfs install --local && git lfs pull` afterwards. Verify with `grep -rl 'git-lfs.github.com/spec' --include='*.usd' .`, which must print nothing.
- **Context:** Robot assets, `UNITREE_MODEL_DIR` in `source/unitree_rl_lab/unitree_rl_lab/assets/robots/unitree.py`.

### Uninstalling a CUDA 13 `nvidia-*` wheel can delete torch's CUDA 12 libraries
- **Pattern:** An unconstrained install pass briefly pulled a CUDA 13 torch, leaving `nvidia-*-cu13` wheels behind after torch was re-pinned to `2.7.0+cu128`. `nvidia-cudnn-cu13` and `nvidia-nccl-cu13` install into the same `nvidia/cudnn/` and `nvidia/nccl/` paths as the `-cu12` wheels, so `pip uninstall` of the cu13 wheels deleted files the cu12 wheels own, and `import torch` failed with `libcudnn.so.9: cannot open shared object file`.
- **Correction:** Before uninstalling leftovers, check each wheel's RECORD for files shared with another installed distribution (`importlib.metadata` `files`), and only remove wheels with none shared. Repair with `pip install --force-reinstall --no-deps nvidia-cudnn-cu12==<ver> nvidia-nccl-cu12==<ver>`. Better: build the env in one pass with `scripts/setup/constraints.txt` applied from the start, so a foreign torch is never pulled.
- **Context:** pip/conda env cleanup, PyTorch CUDA wheels.

### `isaaclab.sh --conda` clears the *active* env's activation hook
- **Pattern:** In IsaacLab v2.3.2, `setup_conda_env` runs `rm -f ${CONDA_PREFIX}/etc/conda/activate.d/setenv.sh` before it activates the target env, so it deletes the hook of whichever env is active when it is invoked. This is from reading `isaaclab.sh`; it was avoided rather than observed.
- **Correction:** Create the env first (`conda env create -f environment.yml -n <name>`), activate it, then run `./isaaclab.sh --conda <name>` from inside it.
- **Context:** IsaacLab v2.3.2 `isaaclab.sh`, conda env setup.

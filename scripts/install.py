#!/usr/bin/env python3
"""Install or remove the capsule without replacing dictation settings."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = {
    'enabled': True,
    'frontend': 'quickshell',
    'style': 'flow-pill',
    'layout': 'custom',
    'palette': 'package',
    'position': 'bottom-center',
    'width_px': 116,
    'height_px': 34,
    'margin_px': 48,
    'opacity': 1.0,
}


def xdg(variable, default):
    return Path(os.environ.get(variable) or Path.home() / default)


def exists(path):
    return path.exists() or path.is_symlink()


def copy_path(source, destination):
    if source.is_symlink():
        destination.symlink_to(os.readlink(source), target_is_directory=source.is_dir())
    else:
        shutil.copytree(source, destination, symlinks=True)


def edit_settings(config, values):
    for key, value in values.items():
        command = ['voxtype', '--config', str(config), 'config']
        if value is None:
            command += ['unset', 'osd.' + key]
        else:
            literal = str(value).lower() if isinstance(value, bool) else str(value)
            command += ['set', 'osd.' + key, literal]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def restart_if_running(no_restart):
    if no_restart:
        print('Restart Voxtype when ready: systemctl --user restart voxtype')
        return
    active = subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'voxtype'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if active.returncode != 0:
        print('Voxtype is not running. Start it with: systemctl --user start voxtype')
        return
    result = subprocess.run(['systemctl', '--user', 'restart', 'voxtype'])
    if result.returncode:
        print('Files are installed. Restart Voxtype manually when ready.', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--uninstall', action='store_true', help='restore previous overlay settings')
    parser.add_argument('--no-restart', action='store_true', help='leave the running service alone')
    args = parser.parse_args()
    for binary in ('voxtype', 'qs', 'voxtype-audio-bridge'):
        if not shutil.which(binary):
            raise SystemExit(f'Missing {binary}. Install and configure Voxtype + Quickshell first.')
    version = subprocess.check_output(['voxtype', '--version'], text=True)
    match = re.search(r'(\d+)\.(\d+)\.(\d+)', version)
    if not match or tuple(map(int, match.groups())) < (1, 1, 0):
        raise SystemExit('Voxtype 1.1.0 or newer is required for custom style packages.')
    runtime = xdg('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')
    state_file = runtime / 'voxtype/state'
    if state_file.exists() and state_file.read_text().strip() in ('recording', 'streaming', 'transcribing'):
        raise SystemExit('Finish the current dictation, then run the installer again.')
    config = xdg('XDG_CONFIG_HOME', '.config') / 'voxtype/config.toml'
    if not config.is_file():
        raise SystemExit(f'Configure Voxtype first; no configuration found at {config}.')
    paths = {
        'style': xdg('XDG_CONFIG_HOME', '.config') / 'voxtype/osd/flow-pill',
        'frontend': xdg('XDG_DATA_HOME', '.local/share') / 'voxtype/quickshell',
    }
    storage = xdg('XDG_STATE_HOME', '.local/state') / 'voxtype-flow-pill'
    marker = storage / 'install-state.json'
    previous = json.loads(marker.read_text()) if marker.exists() else None
    if previous and (previous['config'] != str(config) or previous['paths'] != {k: str(v) for k, v in paths.items()}):
        raise SystemExit('XDG paths changed since installation. Use the original paths to uninstall first.')
    if args.uninstall and not previous:
        raise SystemExit('No installation record found; nothing to uninstall.')
    backup = storage / 'backups' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True)
    saved_config = backup / 'config.toml'
    shutil.copy2(config, saved_config)
    current = tomllib.loads(config.read_text())
    originals = previous['originals'] if previous else {key: current.get('osd', {}).get(key) for key in SETTINGS}
    first_backups = previous['backups'].copy() if previous else {}
    moved, written = [], []
    try:
        for name, target in paths.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            old = backup / name
            if exists(target):
                shutil.move(str(target), str(old))
                moved.append((target, old))
            if not previous:
                first_backups[name] = str(old) if exists(old) else None
            if args.uninstall:
                original = first_backups.get(name)
                if original:
                    copy_path(Path(original), target)
                    written.append(target)
            else:
                source = ROOT / ('quickshell' if name == 'frontend' else 'style')
                copy_path(source, target)
                written.append(target)
        edit_settings(config, originals if args.uninstall else SETTINGS)
        if args.uninstall:
            marker.unlink()
        else:
            record = {'config': str(config), 'paths': {k: str(v) for k, v in paths.items()},
                      'originals': originals, 'backups': first_backups}
            temporary = marker.with_suffix('.tmp')
            temporary.write_text(json.dumps(record, indent=2) + '\n')
            temporary.replace(marker)
    except Exception:
        shutil.copy2(saved_config, config)
        for target in reversed(written):
            if target.is_symlink():
                target.unlink()
            elif target.exists():
                shutil.rmtree(target)
        for target, old in reversed(moved):
            shutil.move(str(old), str(target))
        raise
    print('Restored the previous overlay.' if args.uninstall else 'Installed Voxtype Flow Pill.')
    print(f'Backups: {backup}')
    restart_if_running(args.no_restart)


if __name__ == '__main__':
    main()

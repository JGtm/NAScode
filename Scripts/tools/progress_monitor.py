#!/usr/bin/env python3
"""
progress_monitor.py
Surveille un répertoire contenant des fichiers de progression (writer outputs)
et affiche une ligne par job, mise à jour en place via codes ANSI.
Usage:
  python3 progress_monitor.py --dir /tmp/prog --refresh 0.7

Options:
  --plain pour imprimer sans contrôle ANSI (utile sur consoles sans support ANSI)
"""
import time, argparse, os, sys


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--dir', required=True, help='Directory where job progress files are written')
    p.add_argument('--refresh', type=float, default=0.5)
    p.add_argument('--plain', action='store_true', help='No ANSI cursor control, print changes as lines')
    return p.parse_args()


def read_progress_file(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            line = f.readline().strip()
            if not line:
                return None
            parts = line.split('|')
            if len(parts) >= 3:
                name = parts[0]
                percent = parts[1]
                cur = parts[2]
                return name, percent, cur
    except Exception:
        return None


def clear_lines(n):
    for _ in range(n):
        sys.stdout.write('\x1b[1A')  # up
        sys.stdout.write('\x1b[2K')  # erase line


def main():
    args = parse_args()
    prog_dir = args.dir
    prev_keys = []
    try:
        while True:
            try:
                files = sorted([f for f in os.listdir(prog_dir) if f.endswith('.txt')])
            except Exception:
                files = []
            entries = []
            for fname in files:
                path = os.path.join(prog_dir, fname)
                data = read_progress_file(path)
                if data:
                    entries.append((fname, *data))
            keys = [e[0] for e in entries]
            if not args.plain:
                if prev_keys:
                    clear_lines(len(prev_keys))
                for e in entries:
                    _, name, percent, cur = e
                    label = name if name else e[0]
                    sys.stdout.write(f'{label:30} {percent:6}%  {cur}s\n')
                sys.stdout.flush()
            else:
                for e in entries:
                    _, name, percent, cur = e
                    label = name if name else e[0]
                    print(f'{label:30} {percent:6}%  {cur}s')
            prev_keys = keys
            time.sleep(args.refresh)
    except KeyboardInterrupt:
        print('\nMonitor stopped')

if __name__ == '__main__':
    main()

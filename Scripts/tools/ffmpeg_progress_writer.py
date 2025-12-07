#!/usr/bin/env python3
"""
ffmpeg_progress_writer.py
Lit la sortie -progress de ffmpeg depuis stdin et écrit périodiquement
un fichier de progression atomique contenant: name|percent|current_seconds
Usage:
  python3 ffmpeg_progress_writer.py --duration 3600 --job-file /tmp/prog/job_1.txt --name job1
"""
import sys, argparse, time, os

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--duration', type=float, required=True)
    p.add_argument('--job-file', required=True, help='Path to write progress for this job')
    p.add_argument('--name', default='')
    p.add_argument('--interval', type=float, default=1.0)
    return p.parse_args()


def write_progress(path, name, percent, current):
    tmp = path + '.tmp'
    try:
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(f'{name}|{percent:.2f}|{int(current)}\n')
        os.replace(tmp, path)
    except Exception:
        try:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(f'{name}|{percent:.2f}|{int(current)}\n')
        except Exception:
            pass


def main():
    args = parse_args()
    duration = max(1.0, args.duration)
    last_write = 0
    current_time = 0.0

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if line.startswith('out_time_us='):
            try:
                us = float(line.split('=', 1)[1])
                current_time = us / 1_000_000.0
            except Exception:
                continue
        elif line.startswith('out_time='):
            t = line.split('=', 1)[1].split('.')[0]
            try:
                h, m, s = map(int, t.split(':'))
                current_time = h * 3600 + m * 60 + s
            except Exception:
                pass
        elif line.startswith('progress=') and line.split('=', 1)[1] == 'end':
            current_time = duration

        now = time.time()
        percent = min(100.0, (current_time / duration) * 100.0)
        if now - last_write >= args.interval or percent >= 99.9:
            write_progress(args.job_file, args.name, percent, current_time)
            last_write = now

    # final write
    write_progress(args.job_file, args.name, 100.0, duration)

if __name__ == '__main__':
    main()

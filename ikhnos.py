#!/usr/bin/env python
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "ephem",
#     "matplotlib",
#     "mutagen",
#     "numpy",
#     "pillow",
#     "platformdirs",
#     "requests",
# ]
# ///

import re
import platform
import subprocess
import sys
from urllib.parse import urlsplit
from PIL import Image
import ephem
import datetime
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import numpy as np
import requests
import json
import shutil
from mutagen.oggvorbis import OggVorbis
import re
import os.path
import argparse
import pathlib
from matplotlib.offsetbox import AnchoredText
from matplotlib.gridspec import GridSpec
from platformdirs import user_cache_dir
from pathlib import Path

USE_XDG = True

if USE_XDG:
    APP_NAME = 'ikhnos'
    APP_AUTHOR = 'adamkalis'
    CACHE_DIR = Path(user_cache_dir(APP_NAME, APP_AUTHOR))
else:
    CACHE_DIR = Path('.')


DEMODDATA_FILENAME_PATTERN = r'data_(\d+)_(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})'
DEMODDATA_FILENAME_TIME_FORMAT = '%Y-%m-%dT%H-%M-%S'
class NoAudioError(Exception):
    pass

FREQ_RANGES = [24.0, 25, 29.0, 30.4, 33.2, 38.5, 50, 69.0, 77.0, 83.8, 100, 115.2, 160,174, 200, 230.4, 300]


def parse_args():
    parser = argparse.ArgumentParser(description='Analyze observations')

    parser.add_argument('observations', nargs='+', type=int,
                        help='One or more observation IDs from SatNOGS Network')
    parser.add_argument('-t', '--tle-path', nargs='?', const='tle', default='tle', type=pathlib.Path,
                        help='Path of the TLE file, if not set the default value is "tle" in the current directory')
    parser.add_argument('-f', '--frequency-offset', nargs='?', const=0.0, default=0.0, type=float,
                        help='Offset in KHz to add to the expected center frequency, this can be negative or positive number, default value: 0.0')
    parser.add_argument('-r', '--frequency-range', nargs='?', const=24.0, default=24.0, type=float, choices=FREQ_RANGES,
                        help='The plus-minus KHz from the centered frequency as it is in the X axis in observation waterfall, default value: 24.0')
    parser.add_argument('-d', '--observation-duration', nargs='?', default=0, type=int, help='Set observation duration')
    parser.add_argument('-e', '--tle-epoch-threshold', nargs='?', const=5, default=25, type=int,
                        help='Set the threshold of the difference of observation start time and TLE epoch in days, default value: 5')
    parser.add_argument('--store-tle', action='store_true', help='Append observation tle to the TLE file before plotting')
    parser.add_argument('-C', '--keep-created-files', action='store_true', help='Keep files created by analysis')
    parser.add_argument('-A', '--keep-audio', action='store_true', help='Keep downloaded audio file')
    parser.add_argument('-W', '--keep-waterfall', action='store_true', help='Keep downloaded waterfall file')
    parser.add_argument('--open', action='store_true', help='Open generated images with the default Image Viewer')
    parser.add_argument('-v', '--verbose', action='store_true', help='Be more verbose')

    args = parser.parse_args()
    plt.switch_backend('Agg')

    # Check tle file exists
    if not args.tle_path.exists():
        print(f"Error: TLE input file not found. No such file: '{args.tle_path}'")
        sys.exit(1)

    return args


def fetch_observation(observation_id):
    observation_path = CACHE_DIR / f'{observation_id:d}.json'

    if not observation_path.exists():
        print(f"Requesting observation {observation_id:d}")
        r = requests.get(f'https://network.satnogs.org/api/observations/{observation_id:d}/?format=json')
        observation = json.loads(r.content.decode('utf8'))

        with open(observation_path, 'w') as fp:
            json.dump(observation, fp, indent=2)
    else:
        with open(observation_path) as fp:
            observation = json.load(fp)

    print("Downloading the observation page for getting frequency and tle")
    observation_link = f"https://network.satnogs.org/observations/{observation_id:d}"
    obs_html = requests.get(observation_link).content
    tle_regex = r"<pre.*>(1 .*)<br>(2 .*)</pre>"
    tle_matches = re.search(tle_regex, obs_html.decode("utf-8"))
    tle = [tle_matches.group(1), tle_matches.group(2)]

    sat_name_regex = r"data-target=\"#SatelliteModal\" data-id=\".*\">\n.*- (.*)"
    sat_name_matches = re.search(sat_name_regex, obs_html.decode("utf-8"))
    sat_name = sat_name_matches[1]

    freq_regex = r"(\d*\.\d*) (\w)Hz"
    freq_matches = re.findall(freq_regex, obs_html.decode("utf-8")).pop()
    if freq_matches[1] == 'G':
        freq0 = float(freq_matches[0]) * 1000
    elif freq_matches[1] == 'M':
        freq0 = float(freq_matches[0])
    else:
        raise NotImplementedError

    audio_path = CACHE_DIR / f'{observation_id:d}.ogg'
    waterfall_path = CACHE_DIR / f'{observation_id:d}.png'
    output_path = Path('.') / sat_name / f'{observation_id:d}'

    # Check output path exists
    if not output_path.exists():
        output_path.mkdir(parents=True)

    if not os.path.isfile(audio_path):
        if observation['payload']:
            print("Downloading " + observation['payload'] + ' for getting the right duration')
            observation_ogg_data = requests.get(observation['payload'], stream=True).content
        elif observation['archive_url']:
            print("Downloading " + observation['archive_url'] + ' for getting the right duration')
            observation_ogg_data = requests.get(observation['archive_url'], stream=True).content
        else:
            raise NoAudioError
        with open(audio_path, 'wb') as out_file:
            out_file.write(observation_ogg_data)

    if not os.path.isfile(waterfall_path):
        print("Downloading " + observation['waterfall'] + ' for the background image')
        img_data = requests.get(observation['waterfall']).content
        with open(waterfall_path, 'wb') as handler:
            handler.write(img_data)

    return observation, tle, freq0, sat_name


def plot_overlay(freq_limits, time_limits):
    fig = plt.figure(figsize=(10 * 0.8,20))
    ax = fig.add_subplot(111)
    ax.set_ylabel("Time (seconds)")
    ax.set_xlabel("Frequency (kHz)")
    ax.set_xlim(*freq_limits)
    ax.set_ylim(*time_limits)
    ax.tick_params(axis='x', colors='red')
    ax.tick_params(axis='y', colors='red')
    return fig, ax


def plot_textbox(observation_id, ax, observation, tle_basename):
    fig_label = f"SatNOGS Observation {observation_id:d}\nStation: {observation['ground_station']}-{observation['station_name']}\n{observation['start']}\n{observation['end']}\ntle: {tle_basename}"
    at = AnchoredText(fig_label, prop=dict(size=15), frameon=True, loc='upper left')
    at.patch.set_boxstyle("round,pad=0.,rounding_size=0.2")
    ax.add_artist(at)


def plot_overlay_new(plot_metadata):
    # Read plot metadata
    figsize = plot_metadata['figsize']
    gridspec = plot_metadata['gridspec']
    xlim_kHz = plot_metadata['xlim_kHz']
    ylim_s = plot_metadata['ylim_s']
    ylim_num = plot_metadata['ylim_num']

    # Generate figure and axes
    gs = GridSpec(**gridspec)
    fig = plt.figure(figsize=figsize)
    ax_utc = fig.add_subplot(gs[0])

    ax_utc.set_xlabel("Frequency (kHz)", color='red')
    ax_utc.set_xlim(*xlim_kHz)

    ax_seconds = ax_utc.twinx()
    ax_seconds.set_ylim(*ylim_s)
    ax_seconds.set_ylabel("Time (seconds)", color='red')

    ax_utc.tick_params(axis='x', colors='red')
    ax_utc.tick_params(axis='y', colors='red')
    ax_seconds.tick_params(axis='y', colors='red')

    # Add UTC time labels
    ax_utc.set_ylim(*ylim_num)
    ax_utc.set_ylabel('Time (UTC)', color='red')
    ax_utc.yaxis_date()
    ax_utc.yaxis.set_major_locator(mdates.MinuteLocator(interval=1))
    ax_utc.yaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))

    for spine in ax_seconds.spines.values():
        spine.set_color('red')

    return fig, ax_seconds, ax_utc


def combine_images(background, overlay, output_filename):
    background_img = Image.open(background)
    background_img = background_img.convert("RGBA")

    overlay_img = Image.open(overlay)
    overlay_img = overlay_img.convert("RGBA")

    ov = Image.new('RGBA',background_img.size, (0, 0, 0, 0))
    ov.paste(overlay_img, (0,0))
    background_img.paste(ov, (0,0), ov)
    background_img.save(output_filename, "PNG")

    background_img.close()
    overlay_img.close()


def parse_demoddata_timestamps(observation):
    """
    Parse timestamps from URL path of demoddata objects in observation metadata
    """
    times = []
    for item in observation['demoddata']:
        filename = Path(urlsplit(item['payload_demod']).path).name
        match = re.match(DEMODDATA_FILENAME_PATTERN, filename)
        if match:
            time_str = match.group(2)
            time = datetime.datetime.strptime(time_str, DEMODDATA_FILENAME_TIME_FORMAT)
            # time = time.astimezone(datetime.timezone.utc)
            times.append(time)
    return times


def run_ikhnos(observation_id, observation, tle, freq0, sat_name, args):
    audio_path = CACHE_DIR / f'{observation_id:d}.ogg'
    waterfall_path = CACHE_DIR / f'{observation_id:d}.png'
    output_path = Path('.') / sat_name / f'{observation_id:d}'

    # Read satnogs waterfall plot metadata (if available)
    with Image.open(waterfall_path) as image:
        plot_metadata = (
            json.loads(image.info["satnogs:wf-plot"])
            if "satnogs:wf-plot" in image.info.keys()
            else None
        )

    tstart = observation['start'].replace('Z', '')
    start = datetime.datetime.strptime(tstart, "%Y-%m-%dT%H:%M:%S")
    ystart = datetime.datetime(start.year, 1, 1)

    #+1 day in timedelta as TLE show the day and a fraction of it so Jan 1st is 1 not 0.
    obs_epoch_day = ((start - ystart).total_seconds() + datetime.timedelta(days=1).total_seconds()) / datetime.timedelta(days=1).total_seconds()
    if args.observation_duration == 0:
        f = OggVorbis(audio_path)
        nseconds = int(round(f.info.length))
    else:
        nseconds = args.observation_duration

    tle_file = args.tle_path
    tle_basename = os.path.basename(tle_file)
    with open(tle_file) as f:
        tle_lines = f.read().splitlines()
    if not tle_lines:
        print(f"ERROR: TLE file is empty. File does not contain any lines: '{tle_file}'")
        sys.exit(1)
    tles = []
    for i in range(0, len(tle_lines), 3):
         tles.append(tle_lines[i:i + 3])

    tle_sets_read = 0
    for tba_tle in tles:
        overlay_path = CACHE_DIR / f"{observation_id:d} {tba_tle[0].replace('/','_')}_freq_diff.png"

        epoch_regex = r".{20}\s*(\d*\.\d*)"
        epoch_matches = re.search(epoch_regex, tba_tle[1])
        epoch_day = epoch_matches.group(1)
        obs_tle_epochs_diff = float(epoch_day) - obs_epoch_day
        bef_after = 'B'
        if obs_tle_epochs_diff > 0:
            bef_after = 'A'
        if abs(obs_tle_epochs_diff) > args.tle_epoch_threshold:
            print("TLE too old/new: Epoch differs by more than {:.1f} days\n"
                  "from observation start time (threshold: {:.1f} days)".format(
                    obs_tle_epochs_diff,
                    args.tle_epoch_threshold))
            continue
        tle_sets_read += 1
        print('%s - %s - %s' % (tle_sets_read, obs_tle_epochs_diff, bef_after))

        # Read NORAD and COSPAR ID for this TLE
        obj_regex = r"1 (.....). (........)"
        [(norad_id, cospar_id)] = re.findall(obj_regex, tba_tle[1])

        t, dfreq, dfreqt = propagate(observation, start, nseconds, freq0, tle, tba_tle)

        if plot_metadata:
            # "new" method: Create figure and axes from plot metadata
            fig, ax, ax_utc = plot_overlay_new(plot_metadata)
        else:
            # "deprecated" method: Create figure and axes from collected information
            fig, ax = plot_overlay(
                freq_limits=(-args.frequency_range, args.frequency_range),
                time_limits=(0, nseconds),
            )
        # Add label with observation_id
        plot_textbox(observation_id, ax, observation, tle_basename)
        # Plot line with propagation results
        ax.plot(dfreq  + args.frequency_offset, t, color='red', linewidth=1)

        # Terrestrial transmission
        ax.plot(dfreqt - 5  + args.frequency_offset, t, color='purple', linewidth=1)

        if plot_metadata and observation['demoddata']:
            timestamps = np.array(parse_demoddata_timestamps(observation))
            x = np.zeros_like(timestamps) + 0.95 * ax_utc.get_xlim()[0]
            y = timestamps
            ax_utc.plot(x, y, marker='*', linestyle='', color='red', markersize=10)

        # bbox_inches='tight' was always used before the client started to create metadata
        bbox_inches = 'tight' if not plot_metadata else None
        fig.savefig(overlay_path, bbox_inches=bbox_inches, transparent=True)
        plt.close(fig)

        combined_path = output_path / (tstart + '_' + str(observation_id) + '_' + norad_id + '_' + cospar_id.replace(' ', '') + '_'+ tba_tle[0].replace(' ','-').replace('/','_') + '_' + str(abs(obs_tle_epochs_diff)) + '_' + bef_after + '_r' + str(args.frequency_range) + '_f' + str(args.frequency_offset) + ".png")
        combine_images(
            background=waterfall_path,
            overlay=overlay_path,
            output_filename=combined_path,
        )
        print(f"Output written to '{combined_path}'")
        if args.open and platform.system() == 'Linux':
            subprocess.call(['xdg-open', combined_path])

        if not args.keep_created_files:
            os.remove(overlay_path)

    if not args.keep_audio:
       os.remove(audio_path)
    if not args.keep_waterfall:
       os.remove(waterfall_path)


def propagate(observation, start, nseconds, freq0, tle, tba_tle):
    satellite1 = ephem.readtle('sat', tle[0], tle[1])
    satellite2 = ephem.readtle(tba_tle[0], tba_tle[1], tba_tle[2])

    observer = ephem.Observer()
    observer.lat = str(observation['station_lat'])
    observer.lon = str(observation['station_lng'])
    observer.elevation = observation['station_alt']

    times = [start+datetime.timedelta(seconds=s) for s in range(0, nseconds)]

    v1 = []
    v2 = []
    vt = []
    for t in times:
        observer.date = t
        satellite1.compute(observer)
        satellite2.compute(observer)
        v1.append(satellite1.range_velocity)
        v2.append(satellite2.range_velocity)
        vt.append(0)

    freq1 = freq0*(1.0-np.array(v1)/299792458.0)
    freq2 = freq0*(1.0-np.array(v2)/299792458.0)
    freqt = freq0*(1.0-np.array(vt)/299792458.0)
    dfreq = (freq2-freq1)*1000.0
    dfreqt = (freqt-freq1)*1000.0

    t = np.arange(nseconds)
    return t, dfreq, dfreqt


def main():
    args = parse_args()
    for observation_id in args.observations:
        try:
            observation, tle, freq0, sat_name = fetch_observation(observation_id)
        except NoAudioError:
            print(f"Warning: No audio file, skipping observation {observation_id:d}")
            continue

        if args.verbose:
            print(observation)

        if args.store_tle:
            with open(args.tle_path, 'a') as fp:
                fp.write(f'TLE in Observation {observation_id}\n')
                fp.write(observation['tle1'] + '\n')
                fp.write(observation['tle2'] + '\n')

        run_ikhnos(observation_id, observation, tle, freq0, sat_name, args)


if __name__ == '__main__':
    main()

#!/usr/bin/env bash
# Create TLE from SatNOGS observation as fast as possible
# command: auto.sh <satnogs_observation_id>
# Copyleft 2026 hobisatelit
# https://github.com/hobisatelit/
# License: GPL-3.0-or-later
# forked and inspired from verdantfoster:
# https://community.libre.space/t/work-in-progress-automated-workflow-satnogs-waterfall-tabulation-to-strf/14328

# Configuration
OUTPUT_DIR="/tmp/tle"

##########################################
VERSION="0.01"
MAGIC="25sfefef"

show_help() {
	echo "Create TLE from SatNOGS observation as fast as possible"
	echo "Usage: $0 [options] satnogs_observation_id"
	echo "Options:"
	echo "	-h, --help	show this help"
	echo "	-m, --magic	series of STRF RFFIT command shortcut, default: $MAGIC"
	echo "	-v. --version	version"
	echo ""
	echo "Example:"
	echo "$0 13266946"
}
show_note() {
	echo "→ Note:
	In the next step, you will see the waterfall image.
	- Click on the signal in the waterfall to create a dot marker
	  (ensure the magnifying glass is deselected)
	- Click the magnifying glass to zoom in.
	- Click the house icon to reset zoom.
	- Press U to undo.
	- When finished, press F to save and then close the window.

	Press any key to continue..."
	read	
}
show_note2() {
	echo "→ Note:
	Look at the top left corner of the 'TLE' window and
	enter the name in the 'TLE filename to write' field."
}

main() {
	if [ "$#" -eq 0 ]; then
		show_help
		exit 0
	fi
		
	SETTING_FILE="settings.py"
	DEPS=("python3" "xdotool" "xterm" "rffit" "import" "tail" "awk" "bc" "date" "skill")
	SATNO_WATERFALL_TAB="satnogs_waterfall_tabulation_helper.py"

	if [[ ! -f "$SETTING_FILE" || ! -f "$SATNO_WATERFALL_TAB" ]]; then
		echo "Error: Please run this script same directory with $SATNO_WATERFALL_TAB"
		exit 1
	fi

	# Check if all programs are installed
	for DEP in "${DEPS[@]}"; do
		if ! command -v "$DEP" &> /dev/null; then
			echo "Error: $DEP is not installed. Please install it first."
			exit 1
		fi
	done
	
	while [[ $# -gt 0 ]]; do
		case $1 in
			-h|--help)
				show_help
				exit 0
				;;
			-m|--magic)
				if [[ -n $2 ]]; then
					MAGIC="$2"
					shift
				else
					echo "Error: $1 $2 not valid value"
					exit 1
				fi
				;;
			-v|--version)
				echo "🛰️$0 v$VERSION by https://github.com/hobisatelit"
				exit 0
				;;
			-*)
				echo "Unknown option: $1" >&2
				exit 1
				;;
			*)
				#observation
				if [[ ! $1 =~ ^[0-9]+$ ]]; then
					echo "Error: Satnogs Observation ID should be number!"
					echo "Example: $0 13266938"
					exit 1
				fi
				OBS_ID=$1		
		esac
		shift 
	done

	HOME_DIR=$(grep -E "^home_dir =" "$SETTING_FILE" | sed "s/home_dir = os.path.expanduser('\(.*\)')/\1/")
	DATA_DIR=$(grep -E "^data_dir =" "$SETTING_FILE" | sed "s/data_dir = Path(home_dir, '\(.*\)')/\1/")
	HOME_DIR=${HOME_DIR%/}
	HOME_DIR=${HOME_DIR/#\~/$HOME}
	OUTPUT_DIR=${OUTPUT_DIR%/}
	OUTPUT_DIR=${OUTPUT_DIR/#\~/$HOME}
	DATA_DIR=${DATA_DIR%/}
	SATNO_DIR="$HOME_DIR/$DATA_DIR"
	DAT_FILE="$SATNO_DIR/doppler_obs/${OBS_ID}.dat"
	TLE_FILE="$SATNO_DIR/tles/${OBS_ID}.txt"
	SITES_FILE="$SATNO_DIR/sites.txt"

	if [[ ! -f "$DAT_FILE" ]]; then
		show_note
		echo "→ Downloading #$OBS_ID, please wait.."
		source ./bin/activate
		CMD=$(python3 ./$SATNO_WATERFALL_TAB $OBS_ID  2>&1)
		sleep 1
		deactivate
	else
		echo "WARNING: found previous analysis of observation $OBS_ID"
		read -p "Use it? [Enter to continue | n to delete/recreate | other to cancel]:" user_input
		if [[ "$user_input" == "n" || "$user_input" == "N" ]]; then
			echo "→ Remove ${OBS_ID}.dat"
			rm -- "$DAT_FILE"
			main $1
		elif [[ "$user_input" == "y" || "$user_input" == "Y" || -z "$user_input" ]]; then
			:
		else
			exit 0
		fi
	fi


	if [ ! -f $DAT_FILE ]; then
		echo "Error: No observation $OBS_ID.dat found. Please remember to press the F key after editing the waterfall."
		exit 1 
	fi

	if [ ! -f $TLE_FILE ]; then
		echo "Error: No TLE $OBS_ID.txt found. Check your internet connection."
		exit 1
	fi

	SAT_NAME=$(head -n 1 "$TLE_FILE")
    SAT_NAME="${SAT_NAME/#0 /}"
	EPOCH=$(tail -n 1 "$DAT_FILE" | awk '{print $1}')
	EPOCH=$(date -d "@$(echo "($EPOCH + 2400000.5 - 2440587.5) * 86400" | bc)" +"%Y-%m-%d %H:%M:%S")
	EPOCH="${EPOCH// /T}"
	NORAD_ID=$(sed -n '3p' "$TLE_FILE" | awk '{print $2}')
	OUTPUT_DIR="$OUTPUT_DIR/$SAT_NAME/$EPOCH"

	mkdir -p "$OUTPUT_DIR"
	mkdir -p /tmp/data

	echo "→ Copying Obs Data: $OBS_ID"
	cp "$DAT_FILE" "$OUTPUT_DIR/" 2>/dev/null
	cp "$TLE_FILE" "$OUTPUT_DIR/" 2>/dev/null
	cp "$SITES_FILE" "$OUTPUT_DIR/" 2>/dev/null
	cp "$SITES_FILE" "/tmp/data/" 2>/dev/null

	echo "→ Run STRF / RFFIT .."

	export ST_DATADIR="/tmp"
	
	skill pgxwin_server

	exec xterm -geometry 80x24+0+100 -title TLE -e rffit -d $DAT_FILE -c $TLE_FILE -i $NORAD_ID &
	pid=$!

	sleep 2

	#magic touch
	xdotool type --delay 1000 "$MAGIC"
	
	#write command
	xdotool type --delay 1000 "w"

	#screenshot
	window_id=$(xdotool search --pid $pid | head -n 1)
	import -window "$(xdotool search --name 'PGPLOT Window 1' | head -n 1)" "$OUTPUT_DIR/strf.png"
	
    while true; do
		show_note2
        read -p "	Press <ENTER> once you've done.." input
        if [[ $input == "" ]]; then
            break 
        fi
    done
    
	#quit rffit
	skill -p $pid
	skill pgxwin_server
   
    newest_file=$(ls -t * 2>/dev/null | head -n 1)   
    
    #support if tle first line contain 0, because rffit generate sat name without 0
	if [[ "$SAT_NAME" =~ $(head -n 1 -- "$newest_file") ]]; then
        #if [[ $(sed -n '4p' "$newest_file") =~ "measurements" ]]; then
        #    sed -i '4d' "$newest_file" >/dev/null 2>&1
        #fi
		mv $newest_file "$OUTPUT_DIR/$MAGIC-$newest_file"
	fi
		
	echo "→ Saved in: $OUTPUT_DIR"
	#sleep 
	if command -v xdg-open &> /dev/null; then
		xdg-open "$OUTPUT_DIR" >/dev/null 2>&1 &
	fi	
	exit 1 
}

main $*

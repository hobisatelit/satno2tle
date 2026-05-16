#!/usr/bin/env bash
# Create TLE from SatNOGS observation as fast as possible
# command: auto.sh <satnogs_observation_id>
# Copyleft 2026 hobisatelit
# https://github.com/hobisatelit/
# License: GPL-3.0-or-later
# forked and inspired from verdantfoster:
# https://community.libre.space/t/work-in-progress-automated-workflow-satnogs-waterfall-tabulation-to-strf/14328

# Configuration
#OUTPUT_DIR="/tmp/tle"
OUTPUT_DIR="~/hapus"
##########################################
VERSION="0.02"
MAGIC="25sfefef"
arg_magic=false

show_help() {
	echo "Create TLE from SatNOGS observation as fast as possible"
	echo "Usage: $0 [options] satnogs_observation_id"
	echo "Options:"
	echo "	-h, --help	show this help"
	echo "	-m, --magic	series of STRF RFFIT command shortcut, default: $MAGIC"
	echo "	-man, --manual	manual fitting"
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
	- Press u to undo.
	- When finished, press f for save and q for close the window.

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
    
    declare -a OBS_ID
	
	while [[ $# -gt 0 ]]; do
		case $1 in
			-h|--help)
				show_help
				exit 0
				;;
			-m|--magic)
				if [[ -n $2 ]]; then
					MAGIC="$2"
                    arg_magic=true
					shift
				else
					echo "Error: $1 $2 not valid value"
					exit 1
				fi
				;;
			--manual)
				manual=true
				shift
				;;
			-v|--version)
				echo "🛰️$0 v$VERSION by https://github.com/hobisatelit/satno2tle"
				exit 0
				;;
			-*)
				echo "Unknown option: $1" >&2
				exit 1
				;;
			*)
				#observation
				if [[ ! $1 =~ ^[0-9]+$ ]]; then
					echo "Error: Satnogs Observation ID $1 should be number!"
					echo "Example: $0 13266938"
					exit 1
                else
                    OBS_ID[$i]="$1"
                    ((i++))
				fi
				;;
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
    SITES_FILE="$SATNO_DIR/sites.txt"

	declare -A data
    SAT_NAME2=""
	total=$i
	i=0  
    
    #echo "$i < $total"
    source ./bin/activate
    show_note
    while [ $i -lt $total  ]; do
        DAT_FILE="$SATNO_DIR/doppler_obs/${OBS_ID[$i]}.dat"
        TLE_FILE="$SATNO_DIR/tles/${OBS_ID[$i]}.txt"
        
		#echo "dat_file = $DAT_FILE"

		echo "OBSERVATION ${OBS_ID[$i]}"
		
		first_time=false
        if [[ ! -f "$DAT_FILE" ]]; then
            echo "→ Downloading # ${OBS_ID[$i]}, please wait.."
            CMD=$(python3 ./$SATNO_WATERFALL_TAB ${OBS_ID[$i]}  2>&1)
            first_time=true
            sleep 1
        fi
        
        if [[ -f "$DAT_FILE" ]]; then
			if [[ $first_time == false ]]; then
				echo "WARNING: found previous analysis.."
				read -p "Use it? [Enter to continue | n to delete/recreate | other to cancel]:" user_input
			else
				user_input="y"
			fi
			
            if [[ "$user_input" == "n" || "$user_input" == "N" ]]; then
                echo "→ Remove ${OBS_ID[$i]}.dat"
                rm -- "$DAT_FILE"
                main $*
            elif [[ "$user_input" == "y" || "$user_input" == "Y" || -z "$user_input" ]]; then
            
                if [ ! -f $TLE_FILE ]; then
                    echo "Error: No TLE ${OBS_ID[$i]}.txt found. Check your internet connection."
                    exit 1
                fi
                    
				#echo "--------------------"
				#echo "TLE FILE: $TLE_FILE"
				SAT_NAME=$(head -n 1 "$TLE_FILE")
				SAT_NAME="${SAT_NAME/#0 /}"
				EPOCH=$(tail -n 1 "$DAT_FILE" | awk '{print $1}')
				EPOCH=$(date -d "@$(echo "($EPOCH + 2400000.5 - 2440587.5) * 86400" | bc)" +"%Y-%m-%d %H:%M:%S")
				echo "${SAT_NAME} - ${EPOCH} UTC"
				echo ""
        
                if [[ -n "$SAT_NAME2" && "$SAT_NAME2" != "$SAT_NAME" ]]; then
                    echo "Error: Found different satellites ($SAT_NAME, $SAT_NAME2) in observation ${OBS_ID[$i]}. Ensure that you are only observing the same satellite"
                    exit 1 
                fi
                if [ ! -f $DAT_FILE ]; then
                    echo "Error: No observation ${OBS_ID[$i]}.dat found. Please remember to press the f key after editing the waterfall."
                    exit 1 
                fi

                SAT_NAME2=$SAT_NAME
                data["$EPOCH"]="${OBS_ID[$i]}"
            else
                exit 0
            fi
        fi
		((i++)) 
	done
    deactivate
    mkdir -p /tmp/data/cache


    #TLE_FILE="$SATNO_DIR/tles/${sorted_data[0]}.txt"
    TLE_FILE="$SATNO_DIR/tles/${OBS_ID[0]}.txt"
    #TLE_FILE="$SATNO_DIR/tles/${OBS_ID[0]}.txt"
    #SAT_NAME=$(head -n 1 "$TLE_FILE")
    #SAT_NAME="${SAT_NAME/#0 /}"
	NORAD_ID=$(sed -n '3p' "$TLE_FILE" | awk '{print $2}')
    
    # Initialize a variable to hold all contents
    cat_files=""
    output=""

	echo "SORT OBS (UTC)"
    # Iterate over sorted dates and concatenate contents
    while IFS= read -r dt; do
        echo "$dt"
        cat_files+="$SATNO_DIR/doppler_obs/${data[$dt]}.dat "
        output+="${data[$dt]}_"
    done < <(printf "%s\n" "${!data[@]}" | sort -V) 
    
    cat_files="${cat_files% }"
    output="${output%_}"
    

    DAT_FILE="/tmp/data/cache/${output}.dat"

    cat ${cat_files} > "${DAT_FILE}" 2>&1
    
    echo ""
    
    echo "$cat_files > ${DAT_FILE}"
    
    SAT_NAME=$(head -n 1 "$TLE_FILE")
    EPOCH=$(tail -n 1 "$DAT_FILE" | awk '{print $1}')
    start_date=$(head -n 1 "$DAT_FILE" | awk '{print $1}')
    start_date=$(date -d "@$(echo "($start_date + 2400000.5 - 2440587.5) * 86400" | bc)" +"%Y-%m-%dT%H:%M:%S")
    end_date=$(date -d "@$(echo "($EPOCH + 2400000.5 - 2440587.5) * 86400" | bc)" +"%Y-%m-%dT%H:%M:%S")
    EPOCH=$(date -d "@$(echo "($EPOCH + 2400000.5 - 2440587.5) * 86400" | bc)" +"%Y-%m-%d")
    # Convert to seconds
    start_seconds=$(date -d "$start_date" +%s)
    end_seconds=$(date -d "$end_date" +%s)
    duration=$(( (end_seconds - start_seconds) / 3600 ))
    
    echo ""
    
    echo "Duration: $start_date - $end_date ($duration hours)"
    
    #exit 0
    
    if [[ "$arg_magic" == false && $duration -ge 24 ]]; then
		MAGIC="256sfefef"
	fi
            
	OUTPUT_DIR="$OUTPUT_DIR/$SAT_NAME/$EPOCH"
    OUTPUT_DIR="${OUTPUT_DIR// /-}"
    
    mkdir -p "$OUTPUT_DIR"

    echo "Total Observations: $total"
    for obs in "${data[@]}"; do
        echo "→ Copying ${obs}.dat"
        #list_files+=" "$ 
        cp "${SATNO_DIR}/doppler_obs/${obs}.dat" "${OUTPUT_DIR}/" 2>/dev/null
    done

    DAT_FILE2=$DAT_FILE
    DAT_FILE="${OUTPUT_DIR}/${output}.dat"
    
    cp "${DAT_FILE2}" "${DAT_FILE}" 2>&1
	cp "${SITES_FILE}" "${OUTPUT_DIR}/" 2>/dev/null
	cp "${SITES_FILE}" "/tmp/data/" 2>/dev/null

    #exit 0
    
	echo "→ Run STRF / RFFIT .."

	export ST_DATADIR="/tmp"
	
	skill pgxwin_server

	exec xterm -geometry 80x24+0+100 -title TLE -e rffit -d $DAT_FILE -c $TLE_FILE -i $NORAD_ID &
	pid=$!

	sleep 2

	if [[ "$manual" != "true" ]]; then
		#magic touch
		xdotool type --delay 1000 "$MAGIC"
		
		#write command
		xdotool type --delay 1000 "w"
	else
		MAGIC="manual"
	fi
	
    while true; do
		show_note2
        read -p "	Press <ENTER> once you've done.." input
        if [[ $input == "" ]]; then
            break 
        fi
    done
   
    newest_file=$(ls -t * 2>/dev/null | head -n 1)   
    newest_file_basename="${newest_file%.*}"
    information="# ${output}.dat (total: $total obs) (duration: $duration hours) (magic key: $MAGIC)\n# generated using: https://github.com/hobisatelit/satno2tle (v$VERSION)"
    
    #support if tle first line contain 0, because rffit generate sat name without 0
	if [[ "$SAT_NAME" =~ $(head -n 1 -- "$newest_file") ]]; then
        #if [[ $(sed -n '4p' "$newest_file") =~ "measurements" ]]; then
        #    sed -i '4d' "$newest_file" >/dev/null 2>&1
        #fi
        echo -e "$information" >> "$newest_file"
		mv $newest_file "$OUTPUT_DIR/$newest_file_basename-tle.txt"
	fi
    
	#screenshot
	window_id=$(xdotool search --pid $pid | head -n 1)

	import -window "$(xdotool search --name 'PGPLOT Window 1' | head -n 1)" "$OUTPUT_DIR/$newest_file_basename-strf.png"
    
	#quit rffit
	skill -p $pid
	skill pgxwin_server
		
	echo "→ Saved in: $OUTPUT_DIR"
	#sleep 
	if command -v xdg-open &> /dev/null; then
		xdg-open "$OUTPUT_DIR" >/dev/null 2>&1 &
	fi	
	exit 1 
}

main $*

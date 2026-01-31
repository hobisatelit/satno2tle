#!/usr/bin/env bash
# Running multiple ikhnos.py simultaneously as fast as possbile
# command: ichnos.sh [options] obs1[:f] [obs2...] -t tle_file
# Copyleft 2026 hobisatelit
# https://github.com/hobisatelit/
# License: GPL-3.0-or-later

# Configuration
OUTPUT_DIR="/tmp/tle"

##########################################
VERSION="0.01"
# default arguments for ikhnos
arg_r=24
arg_f=0
arg_e=1000
arg_verbose=false

# start counting time
SECONDS=0

show_help() {
	echo "Running multiple ikhnos.py simultaneously as fast as possbile"
	echo "Usage: $0 -t tle_file obs1[:f] [obs2...] [options]"
	echo "Options:"
	echo "	-h, --help	show this help"
	echo "	-t, --tle	TLE file"
	echo "	-v, --verbose	show what happen"
	echo "	    --version	output version information"
	echo "	-r, --range	range frequency, default: $arg_r"
	echo "	 obs1[:f]	frequency offset, default: $arg_f"
	echo ""
	echo "Example:"
	echo "$0 -t lapan-a2_tle.txt 13266944 13266937:-0.8"
}

main() {
	OUTPUT_DIR=${OUTPUT_DIR%/}
	OUTPUT_DIR=${OUTPUT_DIR/#\~/$HOME}
	
	if [ "$#" -eq 0 ]; then
		show_help
		exit 0
	fi

	DEPS=("python3")
	IKHNOS_FILE="ikhnos.py"
	
	if [ ! -f "$IKHNOS_FILE" ]; then
		echo "Error: Please run this script same directory with $IKHNOS_FILE"
		exit 1
	fi
	
	IKHNOS_DIR=$(pwd)
	IKHNOS_FILE_PATH=$(realpath "$IKHNOS_FILE")

	# Check if all programs are installed
	for DEP in "${DEPS[@]}"; do
		if ! command -v "$DEP" &> /dev/null; then
			echo "Error: $DEP is not installed. Please install it first."
			exit 1
		fi
	done
	
	declare -A data
	i=0
		
	while [[ $# -gt 0 ]]; do
		case $1 in
			-h|--help)
				show_help
				exit 0
				;;
			-r|--range)
				if [[ -n $2 && $2 =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
					arg_r="$2"
					shift 
				else
					echo "Error: $1 $2 not valid value"
					exit 1
				fi
				;;
			-t|--tle)
				if [[ -n $2 ]]; then
					arg_t="$2"
					shift 
				else
					echo "Error: $1 $2 not valid value"
					exit 1
				fi
				;;
			-v|--verbose)
				arg_verbose=true
				;;
			   --version)
				echo "$0 v$VERSION by https://github.com/hobisatelit"
				exit 0
				;;
			-*)
				echo "Unknown option: $1" >&2
				exit 1
				;;
			*)
				#observation, with custom frequency offset
				if [[ $1 == *:* ]]; then
					IFS=':' read -r subs1 subs2 <<< "$1"
					if [[ $subs1 =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
						data[$i,0]=$subs1
						data[$i,1]=$subs2
						((i++))
					fi
					
				#observation, set frequency offset to default 0	
				else
					if [[ $1 =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
						data[$i,0]=$1
						data[$i,1]=$arg_f
						((i++))
					fi
				fi
				;;
		esac
		shift 
	done
	
	if [ ${#data[@]} -eq 0 ]; then
		echo "Error: No valid observations id"
		exit 1
	fi
	
	if [[ ! -f "$arg_t" || ! -n "$arg_t" ]]; then
		echo -e "Error: Cannot find TLE file. Please use option -t or --tle\n$arg_t"
		exit 1 
	fi
	
	arg_t=${arg_t/#\~/$HOME}
	TLE_FILE_PATH=$(realpath "$arg_t")
	TLE_BASENAME=$(basename "$TLE_FILE_PATH")
	TLE_BASENAME="${TLE_BASENAME%.*}"
	SAT_NAME=$(head -n 1 "$TLE_FILE_PATH")
	CACHE_DIR="/tmp/data/cache/$TLE_BASENAME"
	IKHNOS_DIR_OUTPUT="$OUTPUT_DIR/$SAT_NAME/ikhnos/$TLE_BASENAME"
	IKHNOS_DIR_DUMP="$OUTPUT_DIR/$SAT_NAME/ikhnos-dump"
	
	source ./bin/activate

	mkdir -p "$IKHNOS_DIR_OUTPUT"
	mkdir -p "$IKHNOS_DIR_DUMP" 
	mkdir -p "$CACHE_DIR" 
	cd "$CACHE_DIR" 

	total=$i
	i=0
	
	echo "🛰️ $SAT_NAME"
	echo "Total observations: $total"
	while [ $i -lt $total  ]; do
		obs="${data[$i,0]}"
		arg_f="${data[$i,1]}"
		echo "→ Processing #$obs"
		if [ "$arg_verbose" = true ]; then
			exec python3 $IKHNOS_FILE_PATH -r "$arg_r" -f "$arg_f" -t "$TLE_FILE_PATH" -e "$arg_e" "$obs" 2>&1 &
		else
			exec python3 $IKHNOS_FILE_PATH -r "$arg_r" -f "$arg_f" -t "$TLE_FILE_PATH" -e "$arg_e" "$obs" >/dev/null 2>&1 &
		fi
		pid=$!
		data_pid["$obs"]=$pid
		((i++)) 
	done
	
	i=0
	finish=0
	flag=false
	spinner=('-' '\\' '|' '/')
	while true; do
		i=0
		while [ $i -lt $total  ]; do
			pid=${data_pid["${data[$i,0]}"]}
			#echo -ne "+ $i - ${data[$i,0]} - $pid - finish $finish = total $total\r"
			for frame in "${spinner[@]}"; do
				echo -ne "$frame \r"
				sleep 0.1
			done
			if [ $pid ]; then
				CMD=$(ps -p "$pid" --no-headers 2>&1)
				if [[ ! "$CMD" ]]; then
					echo "→ Finishing #${data[$i,0]}"
					data_pid["${data[$i,0]}"]=0
					
					newest_file=$(find "$CACHE_DIR" -type f -iname "*${data[$i,0]}*.png" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d ' ' -f 2-)
					if [ "$newest_file" ]; then
					    cp "$newest_file" "$IKHNOS_DIR_DUMP/${data[$i,0]}-$TLE_BASENAME.png"
						mv "$newest_file" "$IKHNOS_DIR_OUTPUT/${data[$i,0]}.png"
						cp "$TLE_FILE_PATH" "$IKHNOS_DIR_OUTPUT/"
					fi
					
					((finish++))
				fi
			fi
			if [ "$finish" = "$total" ]; then
				flag=true
				break
			fi
			((i++)) 
		done
		if $flag; then
			break
		fi
	done

	cd "$IKHNOS_DIR"
	
	deactivate
	
	echo "Saved in: $OUTPUT_DIR"
	echo "Execution time: $SECONDS seconds"
	#sleep 
	if command -v xdg-open &> /dev/null; then
		xdg-open "$IKHNOS_DIR_OUTPUT" >/dev/null 2>&1 &
	fi	
	exit 1 
}

main $*

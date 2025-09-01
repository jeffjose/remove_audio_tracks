#!/bin/bash

# Check if input file is provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <media_file>"
  exit 1
fi

input_file="$1"

# Check if file exists
if [ ! -f "$input_file" ]; then
  echo "Error: File '$input_file' does not exist"
  exit 1
fi

# Get audio track information
echo "Analyzing audio tracks in '$input_file'..."
echo "----------------------------------------"

# Store track information in arrays
tracks=()
track_indices=()

# Get audio track information using ffprobe
while IFS=, read -r index language title; do
  # Store the actual ffmpeg index
  track_indices+=("$index")
  # Create display string (1-based numbering for display)
  display_num=$((${#tracks[@]} + 1))
  track_info="Language: ${language:-unknown}, Title: ${title:-none}"
  tracks+=("$track_info")
  echo "Track $display_num: $track_info"
done < <(ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language:stream_tags=title -of csv=p=0 "$input_file")

echo "----------------------------------------"

# Check if any audio tracks were found
if [ ${#tracks[@]} -eq 0 ]; then
  echo "No audio tracks found in the file."
  exit 0
fi

# Initialize selection array (all selected by default)
selected=()
for i in "${!tracks[@]}"; do
  selected[i]=true
done

# Function to display the menu
display_menu() {
  clear
  echo "Select audio tracks to KEEP in '$input_file':"
  echo "Use ↑/↓ to navigate, SPACE to select/deselect, ENTER to confirm"
  echo "================================================"
  
  for i in "${!tracks[@]}"; do
    if [ $i -eq $cursor ]; then
      # Highlight current line
      if [ "${selected[$i]}" = true ]; then
        echo -e "\e[7m→ [✓] Track $((i+1)): ${tracks[$i]}\e[0m"
      else
        echo -e "\e[7m→ [ ] Track $((i+1)): ${tracks[$i]}\e[0m"
      fi
    else
      # Normal line
      if [ "${selected[$i]}" = true ]; then
        echo "  [✓] Track $((i+1)): ${tracks[$i]}"
      else
        echo "  [ ] Track $((i+1)): ${tracks[$i]}"
      fi
    fi
  done
  
  echo "================================================"
  echo "Press 'q' to quit without making changes"
}

# Initialize cursor position
cursor=0

# Hide cursor
tput civis

# Trap to restore cursor on exit
trap 'tput cnorm' INT TERM EXIT

# Main selection loop
while true; do
  display_menu
  
  # Read single keypress
  IFS= read -rsn1 key
  
  # Handle arrow keys (they send escape sequences)
  if [[ $key == $'\x1b' ]]; then
    read -rsn2 key
    case $key in
      '[A') # Up arrow
        ((cursor--))
        if [ $cursor -lt 0 ]; then
          cursor=$((${#tracks[@]} - 1))
        fi
        ;;
      '[B') # Down arrow
        ((cursor++))
        if [ $cursor -ge ${#tracks[@]} ]; then
          cursor=0
        fi
        ;;
    esac
  elif [[ $key == ' ' ]]; then
    # Space - toggle selection
    if [ "${selected[$cursor]}" = true ]; then
      selected[$cursor]=false
    else
      selected[$cursor]=true
    fi
  elif [[ $key == '' ]]; then
    # Enter - confirm selection
    break
  elif [[ $key == 'q' ]] || [[ $key == 'Q' ]]; then
    # Quit
    tput cnorm
    clear
    echo "Cancelled. No changes made."
    exit 0
  fi
done

# Show cursor again
tput cnorm
clear

# Build list of tracks to keep
tracks_to_keep=""
echo "Selected tracks to keep:"
echo "------------------------"
for i in "${!tracks[@]}"; do
  if [ "${selected[$i]}" = true ]; then
    track_num=$((i+1))
    echo "Track $track_num: ${tracks[$i]}"
    tracks_to_keep="$tracks_to_keep $track_num"
  fi
done

# Exit if no tracks were selected
if [ -z "$tracks_to_keep" ]; then
  echo ""
  echo "No tracks selected. Exiting without making any changes."
  exit 0
fi

echo "------------------------"

# Create temporary file in the same directory
temp_file="${input_file%.*}.temp.${input_file##*.}"

# Build the ffmpeg command
ffmpeg_cmd="ffmpeg -i \"$input_file\""

# First map video stream
ffmpeg_cmd="$ffmpeg_cmd -map 0:v"

# Add the selected audio tracks in order
audio_index=0
for track in $tracks_to_keep; do
  # Convert 1-based index to 0-based for ffmpeg
  zero_based_track=$((track - 1))
  ffmpeg_cmd="$ffmpeg_cmd -map 0:a:$zero_based_track?"
  audio_index=$((audio_index + 1))
done

# Map other streams
ffmpeg_cmd="$ffmpeg_cmd -map 0:s? -map 0:d? -map 0:t?"

# Complete the command with temporary file
ffmpeg_cmd="$ffmpeg_cmd -c copy \"$temp_file\""

echo "Executing: $ffmpeg_cmd"
eval "$ffmpeg_cmd"

if [ $? -eq 0 ]; then
  # If successful, replace original file with temporary file
  mv "$temp_file" "$input_file"
  echo "Successfully modified '$input_file'"
else
  # If failed, remove temporary file
  rm -f "$temp_file"
  echo "Error occurred while processing the file"
  exit 1
fi
